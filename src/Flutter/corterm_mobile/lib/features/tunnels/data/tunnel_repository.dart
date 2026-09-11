import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// 隧道视图（对齐 Gateway `TunnelDto`）。[secret] 仅创建响应里有明文，列表为 null。
class TunnelSummary {
  TunnelSummary({
    required this.tunnelId,
    required this.port,
    required this.url,
    required this.expiresAtUtc,
    this.secret,
  });

  final String tunnelId;
  final int port;
  final String url;
  final String? secret;
  final DateTime expiresAtUtc;

  factory TunnelSummary.fromJson(Map<String, dynamic> json) => TunnelSummary(
        tunnelId: json['tunnelId'] as String,
        port: (json['port'] as num).toInt(),
        url: json['url'] as String? ?? '',
        secret: json['secret'] as String?,
        expiresAtUtc:
            DateTime.tryParse(json['expiresAtUtc'] as String? ?? '')?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Session 端口转发数据源（对齐 Gateway `/api/me/sessions/{id}/tunnels*`）。
class TunnelRepository {
  TunnelRepository(this._client);

  final ApiClient _client;

  /// 列出 session 的隧道。响应为 TunnelListResponse：{tunnels: [...]}。
  Future<List<TunnelSummary>> list(String sessionId) async {
    try {
      final json = await _client.getMap('/api/me/sessions/$sessionId/tunnels');
      final items = (json['tunnels'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(TunnelSummary.fromJson)
          .toList();
      return items;
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<TunnelSummary> create({required String sessionId, required int port}) async {
    try {
      final json = await _client.postMap('/api/me/sessions/$sessionId/tunnels', {'port': port});
      return TunnelSummary.fromJson(json);
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<void> revoke(String tunnelId) async {
    try {
      await _client.delete('/api/me/tunnels/$tunnelId');
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }
}

final tunnelRepositoryProvider = Provider<TunnelRepository>(
    (ref) => TunnelRepository(ref.watch(apiClientProvider)));
