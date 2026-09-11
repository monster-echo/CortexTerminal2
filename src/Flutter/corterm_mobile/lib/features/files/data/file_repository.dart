import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

/// 远程文件（Gateway RemoteFiles：列目录 + 预签名 S3 上传/下载，单笔 ≤50MB）。
class FileRepository {
  FileRepository(this._client, this._bareDio);

  final ApiClient _client;

  /// 预签名 S3 URL 的直传/直取**不能带** Authorization 头，用独立 Dio。
  final Dio _bareDio;

  static const maxTransferBytes = 50 * 1024 * 1024;

  Future<FileListing> list({required String sessionId, required String path}) async {
    Map<String, dynamic> json;
    try {
      json = await _client.getMap(
        '/api/sessions/$sessionId/files',
        query: {'path': path},
      );
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    return FileListing.fromJson(json);
  }

  /// 上传：申请预签名 URL → PUT 到 S3 → complete。返回最终 imageUrl 式路径（供日志）。
  Future<void> upload({
    required String sessionId,
    required String dirPath,
    required String filename,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxTransferBytes) {
      throw ApiException(0, serverMessage: 'file exceeds 50 MB limit');
    }
    final sha256 = _sha256of(bytes);
    Map<String, dynamic> grant;
    try {
      grant = await _client.postMap('/api/sessions/$sessionId/files/uploads', {
        'dirPath': dirPath,
        'filename': filename,
        'sizeBytes': bytes.length,
        'sha256': sha256,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    final uploadUrl = grant['uploadUrl'] as String?;
    final requestId = grant['requestId'] as String?;
    if (uploadUrl == null || requestId == null) {
      throw ApiException(0, serverMessage: 'upload grant missing fields');
    }
    try {
      final res = await _bareDio.put<void>(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {'Content-Length': bytes.length},
          // 显式空 Content-Type 由 S3 预签名的签名决定，不额外添加头。
        ),
      );
      if (res.statusCode != 200) {
        throw ApiException(res.statusCode ?? 0, serverMessage: 'S3 upload failed');
      }
    } on DioException catch (e) {
      throw ApiException(0, serverMessage: 'S3 upload failed: ${e.message}');
    }
    try {
      await _client.postMap(
        '/api/sessions/$sessionId/files/uploads/$requestId/complete',
        null,
      );
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  /// 下载：创建请求 → 轮询 ready → 拉取字节 → 写入临时文件并返回。
  Future<File> download({
    required String sessionId,
    required String path,
    required String filename,
  }) async {
    Map<String, dynamic> created;
    try {
      created = await _client.postMap('/api/sessions/$sessionId/files/downloads', {
        'path': path,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    final requestId = created['requestId'] as String?;
    if (requestId == null || requestId.isEmpty) {
      throw ApiException(0, serverMessage: 'download request missing requestId');
    }
    String? downloadUrl;
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      Map<String, dynamic> status;
      try {
        status = await _client.getMap(
          '/api/sessions/$sessionId/files/downloads/$requestId',
        );
      } on DioException catch (e) {
        ApiClient.throwFor(e);
      }
      final state = status['status'] as String?;
      switch (state) {
        case 'ready':
          downloadUrl = status['downloadUrl'] as String?;
        case 'failed':
          throw ApiException(0, serverMessage: (status['error'] as String?) ?? 'download failed');
        case 'pending':
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        default:
          throw ApiException(0, serverMessage: 'unknown download status: $state');
      }
      if (downloadUrl != null) break;
    }
    if (downloadUrl == null) {
      throw ApiException(0, serverMessage: 'download timed out');
    }
    final res = await _bareDio.get<List<int>>(
      downloadUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final dir = await Directory.systemTemp.createTemp('corterm_dl');
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(res.data ?? const <int>[], flush: true);
    return file;
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
        name: json['name'] as String,
        isDirectory: json['isDirectory'] as bool? ?? false,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        modifiedUtc: (json['modifiedUtc'] as String?) != null
            ? DateTime.parse(json['modifiedUtc'] as String)
            : null,
      );
}

class FileListing {
  const FileListing({required this.path, required this.entries, required this.truncated});

  final String path;
  final List<FileEntry> entries;
  final bool truncated;

  factory FileListing.fromJson(Map<String, dynamic> json) => FileListing(
        path: json['path'] as String? ?? '/',
        entries: ((json['entries'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(FileEntry.fromJson)
            .toList(),
        truncated: json['truncated'] as bool? ?? false,
      );
}

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  return FileRepository(
    ref.watch(apiClientProvider),
    Dio(),
  );
});
