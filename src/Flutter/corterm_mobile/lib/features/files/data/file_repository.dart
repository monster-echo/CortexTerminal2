import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

/// 远程文件 v2（对齐 ArkTS FilesService / Gateway /api/workspaces*）：
/// 文件管理以【工作区】为边界；上传/下载经 Relay（或直连端点）流式直传，
/// PUT/GET 响应即终态，无轮询。端点按优先序逐个尝试（LAN 直连 → 公网直连 → Relay）。
class FileRepository {
  FileRepository(this._client, this._bareDio);

  final ApiClient _client;

  /// 端点直传不能带 Authorization 头，用独立 Dio。
  final Dio _bareDio;

  // ---- 工作区 ----

  Future<List<Workspace>> listWorkspaces() async {
    List<Map<String, dynamic>> raw;
    try {
      final list = await _client.getList('/api/workspaces');
      raw = list.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    return raw.map(Workspace.fromJson).toList();
  }

  Future<Workspace> createWorkspace({
    required String workerId,
    required String name,
    required String rootPath,
  }) async {
    Map<String, dynamic> json;
    try {
      json = await _client.postMap('/api/workspaces', {
        'workerId': workerId,
        'name': name,
        'rootPath': rootPath,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    return Workspace.fromJson(json);
  }

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

  List<String> _readEndpoints(Map<String, dynamic> response) {
    final raw = response['endpoints'] as List<dynamic>? ?? const <dynamic>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((e) => e['url'] as String? ?? '')
        .where((u) => u.isNotEmpty)
        .toList();
  }

  /// 端点协商上传：逐个尝试 PUT，任一成功即返回；全部失败抛最后一次错误。
  /// Web 端不能用流式请求体（浏览器 XHR 不支持），必须整包 bytes 直传，
  /// 且 Content-Length 是浏览器禁用头，不能手动设置。
  Future<void> _putViaEndpoints(List<String> endpoints, Uint8List bytes) async {
    Object? lastError;
    for (final url in endpoints) {
      try {
        final res = await _bareDio.put<void>(
          url,
          data: kIsWeb ? bytes : Stream.fromIterable([bytes]),
          options: Options(
            headers: kIsWeb ? null : {'Content-Length': bytes.length},
            contentType: 'application/octet-stream',
          ),
        );
        if (res.statusCode != null && res.statusCode! < 300) return;
        lastError = 'transfer failed (${res.statusCode})';
      } on DioException catch (e) {
        lastError = e.message ?? e.error ?? e;
      }
    }
    throw ApiException(0, serverMessage: 'Transfer failed: $lastError');
  }

  /// 端点协商下载：逐个尝试 GET，任一成功即返回。
  Future<Uint8List> _getViaEndpoints(List<String> endpoints) async {
    Object? lastError;
    for (final url in endpoints) {
      try {
        final res = await _bareDio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        if (res.statusCode != null && res.statusCode! < 300) {
          return Uint8List.fromList(res.data ?? const <int>[]);
        }
        lastError = 'transfer failed (${res.statusCode})';
      } on DioException catch (e) {
        lastError = e.message ?? e.error ?? e;
      }
    }
    throw ApiException(0, serverMessage: 'Transfer failed: $lastError');
  }

  String _sha256of(Uint8List bytes) => sha256.convert(bytes).toString();
}

/// 工作区（文件管理的边界：绑定一个 Worker + 一个根路径）。
class Workspace {
  const Workspace({
    required this.workspaceId,
    required this.workerId,
    required this.name,
    this.rootPath,
  });

  final String workspaceId;
  final String workerId;
  final String name;
  final String? rootPath;

  String get displayName => name.isNotEmpty ? name : (rootPath ?? workspaceId);

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
        workspaceId:
            (json['workspaceId'] ?? json['id']) as String? ?? '',
        workerId: json['workerId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        rootPath: json['rootPath'] as String?,
      );
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
  const FileListing({
    required this.entries,
    required this.truncated,
  });

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
  return FileRepository(ref.watch(apiClientProvider), Dio());
});
