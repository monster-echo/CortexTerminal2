import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

/// 反馈附件上传结果。
class FeedbackAttachment {
  FeedbackAttachment({required this.uploadUrl, required this.imageUrl});

  final String uploadUrl;
  final String imageUrl;
}

/// 意见反馈数据源（对齐 MAUI SupportService）：
/// 1. POST /api/me/feedback/uploads 换 presigned URL
/// 2. 裸 PUT S3（不带 Bearer，对齐 file_repository 的 _bareDio 模式）
/// 3. POST n8n webhook（timestamp + nonce 结构，返回 ticketId）
class FeedbackRepository {
  FeedbackRepository(this._client, this._webhookUrl);

  final ApiClient _client;

  /// n8n webhook 独立地址（不走 gateway baseUrl）。
  final String _webhookUrl;

  final Dio _bareDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 120),
  ));

  Future<FeedbackAttachment> requestUpload({required String filename}) async {
    try {
      final json = await _client.postMap('/api/me/feedback/uploads', {'filename': filename});
      final uploadUrl = json['uploadUrl'] as String?;
      final rawImageUrl = json['imageUrl'] as String?;
      if (uploadUrl == null || rawImageUrl == null) {
        throw ApiException(0, serverMessage: 'feedback upload: missing uploadUrl/imageUrl');
      }
      // gateway 可能回相对路径，补全为公网 URL（MAUI 同款）。
      final imageUrl = rawImageUrl.startsWith('http')
          ? rawImageUrl
          : '${_client.baseUrl}$rawImageUrl';
      return FeedbackAttachment(uploadUrl: uploadUrl, imageUrl: imageUrl);
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<void> putToStorage({
    required String uploadUrl,
    required Uint8List bytes,
  }) async {
    final res = await _bareDio.put<void>(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(headers: {'Content-Length': bytes.length}),
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode ?? 0, serverMessage: 'feedback upload failed');
    }
  }

  /// 提交反馈工单，返回 ticketId。
  Future<String> submit({
    required String type,
    required String subtype,
    required String content,
    required String contact,
    required String username,
    required String lang,
    required String appVersion,
    required List<String> attachments,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = 'fb-$timestamp-${Random().nextInt(1000000)}';
    final response = await _bareDio.post<Map<String, dynamic>>(
      _webhookUrl,
      data: {
        'type': type,
        'subtype': subtype,
        'content': content,
        'contact': contact,
        'username': username,
        'lang': lang,
        'appVersion': appVersion,
        'timestamp': timestamp,
        'nonce': nonce,
        'attachments': attachments,
      },
    );
    final ticketId = response.data?['ticketId'] as String?;
    if (ticketId == null || ticketId.isEmpty) {
      throw ApiException(0, serverMessage: 'feedback submit: no ticketId');
    }
    return ticketId;
  }

  void dispose() => _bareDio.close();
}

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  final repo = FeedbackRepository(
    ref.watch(apiClientProvider),
    'https://n8n.0x2a.top/webhook/corterm-feedback',
  );
  ref.onDispose(repo.dispose);
  return repo;
});
