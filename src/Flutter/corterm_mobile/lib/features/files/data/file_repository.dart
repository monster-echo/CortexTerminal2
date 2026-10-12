import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../p2p/p2p_channel.dart';
// Web 无 UDP socket，走 stub（抛 P2pException → 规格 §5 端点回落）。
import '../p2p/p2p_stub.dart'
    if (dart.library.io) '../p2p/p2p_transfer.dart'
    as p2p_backend;

/// 远程文件 v2（对齐 ArkTS FilesService / Gateway /api/workspaces*）：
/// 文件管理以【工作区】为边界；上传/下载经 Relay（或直连端点）流式直传，
/// PUT/GET 响应即终态，无轮询。端点按优先序逐个尝试（LAN 直连 → 公网直连 → Relay）。
class FileRepository {
  FileRepository(this._client, this._bareDio, this.transferRoutes);

  final TransferRoutes transferRoutes;

  final ApiClient _client;

  /// 端点直传不能带 Authorization 头，用独立 Dio。
  final Dio _bareDio;

  // ---- 工作区 ----

  // ---- 浏览 ----

  /// 列目录（v2：path '' = 工作区根）。
  Future<FileListing> list({
    required String workspaceId,
    required String path,
  }) async {
    Map<String, dynamic> json;
    try {
      json = await _client.getMap(
        '/api/workspaces/$workspaceId/files',
        query: {'path': path},
      );
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    return FileListing.fromJson(json);
  }

  // ---- Worker 直连通道（IA 约定：ungrouped 会话按终端 cwd 浏览 + 远端选文件夹）----
  // root 由客户端给定（须在用户 home 内，Worker 端校验），path 相对 root。

  Future<FileListing> listForWorker({
    required String workerId,
    required String root,
    String path = '',
  }) async {
    Map<String, dynamic> json;
    try {
      json = await _client.getMap(
        '/api/workers/$workerId/files',
        query: {'root': root, 'path': path},
      );
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    return FileListing.fromJson(json);
  }

  /// 文件夹选择页「新建文件夹」：在 worker 根（如 "~"）下新建目录。
  Future<void> mkdirForWorker({
    required String workerId,
    required String root,
    required String path,
  }) async {
    try {
      await _client.postMap('/api/workers/$workerId/files/mkdir', {
        'root': root,
        'path': path,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<void> uploadForWorker({
    required String workerId,
    required String root,
    required String dirPath,
    required String filename,
    required Uint8List bytes,
  }) async {
    Map<String, dynamic> grant;
    try {
      grant = await _client.postMap('/api/workers/$workerId/files/uploads', {
        'root': root,
        'dirPath': dirPath,
        'filename': filename,
        'sizeBytes': bytes.length,
        'sha256': _sha256of(bytes),
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    final endpoints = _readEndpoints(grant);
    if (endpoints.isEmpty) {
      throw ApiException(0, serverMessage: 'no transfer endpoints');
    }
    await _putViaEndpoints(endpoints, bytes);
  }

  Future<Uint8List> downloadBytesForWorker({
    required String workerId,
    required String root,
    required String path,
  }) async {
    Map<String, dynamic> init;
    try {
      init = await _client.postMap('/api/workers/$workerId/files/downloads', {
        'root': root,
        'path': path,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    final endpoints = _readEndpoints(init);
    if (endpoints.isEmpty) {
      throw ApiException(0, serverMessage: 'no transfer endpoints');
    }
    return _getViaEndpoints(endpoints);
  }

  // ---- 文件变更 ----

  /// 新建目录（仅最后一级，父级不存在服务端报 path_invalid）。
  Future<void> mkdir({
    required String workspaceId,
    required String path,
  }) async {
    try {
      await _client.postMap('/api/workspaces/$workspaceId/files/mkdir', {
        'path': path,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  /// 新建/覆盖文本文件（UTF-8）。
  Future<void> writeText({
    required String workspaceId,
    required String path,
    required String content,
  }) async {
    try {
      await _client.postMap('/api/workspaces/$workspaceId/files/write-text', {
        'path': path,
        'content': content,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  /// 重命名文件或目录（newName 是单段文件名）。
  Future<void> rename({
    required String workspaceId,
    required String path,
    required String newName,
  }) async {
    try {
      await _client.postMap('/api/workspaces/$workspaceId/files/rename', {
        'path': path,
        'newName': newName,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  /// 删除文件或目录（目录递归删除）。
  Future<void> delete({
    required String workspaceId,
    required String path,
  }) async {
    try {
      await _client.postMap('/api/workspaces/$workspaceId/files/delete', {
        'path': path,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  // ---- 上传 ----

  /// 上传：注册 transfer → 端点协商 PUT（响应即终态）。
  Future<void> upload({
    required String workspaceId,
    required String dirPath,
    required String filename,
    required Uint8List bytes,
  }) async {
    Map<String, dynamic> grant;
    try {
      grant = await _client.postMap(
        '/api/workspaces/$workspaceId/files/uploads',
        {
          'dirPath': dirPath,
          'filename': filename,
          'sizeBytes': bytes.length,
          'sha256': _sha256of(bytes),
        },
      );
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    final endpoints = _readEndpoints(grant);
    if (endpoints.isEmpty) {
      throw ApiException(0, serverMessage: 'no transfer endpoints');
    }
    await _putViaEndpoints(endpoints, bytes);
  }

  // ---- 下载 ----

  /// 下载为可分享文件（内存 XFile，三端一致，不落盘）。
  Future<XFile> download({
    required String workspaceId,
    required String path,
    required String filename,
  }) async {
    final bytes = await downloadBytes(workspaceId: workspaceId, path: path);
    return XFile.fromData(bytes, name: filename);
  }

  /// 下载：校验并取端点 → 端点协商 GET 字节。
  Future<Uint8List> downloadBytes({
    required String workspaceId,
    required String path,
  }) async {
    Map<String, dynamic> init;
    try {
      init = await _client.postMap(
        '/api/workspaces/$workspaceId/files/downloads',
        {'path': path},
      );
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    final endpoints = _readEndpoints(init);
    if (endpoints.isEmpty) {
      throw ApiException(0, serverMessage: 'no transfer endpoints');
    }
    return _getViaEndpoints(endpoints);
  }

  // ---- 内部 ----

  List<TransferEndpoint> _readEndpoints(Map<String, dynamic> response) {
    final raw = response['endpoints'] as List<dynamic>? ?? const <dynamic>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => TransferEndpoint(
            e['url'] as String? ?? '',
            e['kind'] as String? ?? 'relay',
          ),
        )
        .where((e) => e.url.isNotEmpty)
        .toList();
  }

  /// 端点协商上传：LAN → p2p → 公网 → Relay 逐个尝试 PUT，任一成功即返回；
  /// 全部失败抛最后一次错误。
  /// Web 端不能用流式请求体（浏览器 XHR 不支持），必须整包 bytes 直传，
  /// 且 Content-Length 是浏览器禁用头，不能手动设置。
  Future<void> _putViaEndpoints(
    List<TransferEndpoint> endpoints,
    Uint8List bytes,
  ) async {
    // 规格 §1/§5：端点协商开始时【并行】启动 p2p 打洞准备。
    final p2pReady = _startP2p(endpoints);
    Object? lastError;

    Future<void> putHttp(String url) async {
      final res = await _bareDio.put<void>(
        url,
        data: kIsWeb ? bytes : Stream.fromIterable([bytes]),
        options: Options(
          headers: kIsWeb ? null : {'Content-Length': bytes.length},
          contentType: 'application/octet-stream',
        ),
      );
      if (res.statusCode == null || res.statusCode! >= 300) {
        throw ApiException(
          res.statusCode ?? 0,
          serverMessage: 'transfer failed (${res.statusCode})',
        );
      }
    }

    // 1) 仅尝试明确标为 LAN 的端点。
    for (final endpoint in endpoints.where((e) => e.kind == 'lan')) {
      try {
        await putHttp(endpoint.url);
        transferRoutes.record('lan');
        unawaited(p2pReady.then((channel) => channel?.close()));
        return;
      } on DioException catch (e) {
        lastError = e.message ?? e.error ?? e;
      }
    }
    // 2) p2p（6s 内打通才算；失败是规格 §5 允许的唯一静默回落点）。
    final channel = await p2pReady;
    if (channel != null) {
      try {
        final target = _p2pTarget(endpoints)!;
        await channel.upload(
          transferId: target.$1,
          token: target.$2,
          bytes: bytes,
        );
        transferRoutes.record('p2p');
        return;
      } on Object {
        // p2p 传输失败（含流被 RST）→ 落下一端点（规格 §5 唯一允许的静默回落）。
      } finally {
        channel.close();
      }
    }
    // 3/4) 公网 → Relay。
    for (final endpoint in endpoints.where((e) => e.kind != 'lan')) {
      try {
        await putHttp(endpoint.url);
        transferRoutes.record(endpoint.kind);
        return;
      } on DioException catch (e) {
        lastError = e.message ?? e.error ?? e;
      }
    }
    throw ApiException(0, serverMessage: 'Transfer failed: $lastError');
  }

  /// 端点协商下载：LAN → p2p → 公网 → Relay 逐个尝试 GET，任一成功即返回。
  Future<Uint8List> _getViaEndpoints(List<TransferEndpoint> endpoints) async {
    // 规格 §1/§5：端点协商开始时【并行】启动 p2p 打洞准备。
    final p2pReady = _startP2p(endpoints);
    Object? lastError;

    Future<Uint8List> getHttp(String url) async {
      final res = await _bareDio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.statusCode != null && res.statusCode! < 300) {
        return Uint8List.fromList(res.data ?? const <int>[]);
      }
      throw ApiException(
        res.statusCode ?? 0,
        serverMessage: 'transfer failed (${res.statusCode})',
      );
    }

    // 1) LAN。
    for (final endpoint in endpoints.where((e) => e.kind == 'lan')) {
      try {
        final bytes = await getHttp(endpoint.url);
        transferRoutes.record('lan');
        unawaited(p2pReady.then((channel) => channel?.close()));
        return bytes;
      } on DioException catch (e) {
        lastError = e.message ?? e.error ?? e;
      }
    }
    // 2) p2p（规格 §5 唯一允许的静默回落点）。
    final channel = await p2pReady;
    if (channel != null) {
      try {
        final target = _p2pTarget(endpoints)!;
        final bytes = await channel.download(
          transferId: target.$1,
          token: target.$2,
        );
        transferRoutes.record('p2p');
        return bytes;
      } on Object {
        // p2p 传输失败（含流被 RST）→ 落下一端点（规格 §5 唯一允许的静默回落）。
      } finally {
        channel.close();
      }
    }
    // 3/4) 公网 → Relay。
    for (final endpoint in endpoints.where((e) => e.kind != 'lan')) {
      try {
        final bytes = await getHttp(endpoint.url);
        transferRoutes.record(endpoint.kind);
        return bytes;
      } on DioException catch (e) {
        lastError = e.message ?? e.error ?? e;
      }
    }
    throw ApiException(0, serverMessage: 'Transfer failed: $lastError');
  }

  /// 并行 p2p 准备（规格 §1/§5，deadline 6s）：打通返回通道，未打通/失败返回 null。
  /// p2p 的任何失败都属于规格允许的「静默落下一端点」，不向上抛。
  Future<P2pChannel?> _startP2p(List<TransferEndpoint> endpoints) async {
    final target = _p2pTarget(endpoints);
    if (target == null) return null;
    try {
      return await p2p_backend.openP2pChannel(
        gatewayBaseUrl: _client.baseUrl,
        transferId: target.$1,
        token: target.$2,
        jwt: _client.tokenStore.token,
      );
    } on Object {
      return null;
    }
  }

  /// 从端点 URL（…/transfer/{id}?token=…）取 p2p 所需 transferId + token。
  (String transferId, String token)? _p2pTarget(
    List<TransferEndpoint> endpoints,
  ) {
    if (endpoints.isEmpty) return null;
    final uri = Uri.parse(endpoints.first.url);
    final segs = uri.pathSegments;
    if (segs.length < 2 || segs[segs.length - 2] != 'transfer') return null;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return null;
    return (segs.last, token);
  }

  String _sha256of(Uint8List bytes) => sha256.convert(bytes).toString();
}

class FileEntry {
  const FileEntry({
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedUtc,
  });

  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedUtc;

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    name: json['name'] as String? ?? '',
    isDirectory: json['isDirectory'] as bool? ?? false,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    modifiedUtc: (json['modifiedUtc'] as String?) != null
        ? DateTime.tryParse(json['modifiedUtc'] as String)
        : null,
  );
}

class FileListing {
  const FileListing({required this.entries, required this.truncated});

  final List<FileEntry> entries;
  final bool truncated;

  factory FileListing.fromJson(Map<String, dynamic> json) => FileListing(
    entries: ((json['entries'] as List<dynamic>?) ?? const <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(FileEntry.fromJson)
        .toList(),
    truncated: json['truncated'] as bool? ?? false,
  );
}

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  final dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 10)
    ..options.receiveTimeout = const Duration(seconds: 60);
  ref.onDispose(dio.close);
  return FileRepository(
    ref.watch(apiClientProvider),
    dio,
    ref.watch(transferRoutesProvider),
  );
});

class TransferEndpoint {
  const TransferEndpoint(this.url, this.kind);
  final String url;
  final String kind;
}

/// Records completed transfers only; LAN direct is distinct from UDP hole punching.
class TransferRoutes extends ValueNotifier<List<(DateTime, String)>> {
  TransferRoutes() : super(const []);
  void record(String kind) {
    value = [(DateTime.now(), kind), ...value].take(20).toList();
  }
}

final transferRoutesProvider = Provider<TransferRoutes>((ref) {
  final routes = TransferRoutes();
  ref.onDispose(routes.dispose);
  return routes;
});
