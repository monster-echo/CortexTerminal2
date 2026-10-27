import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// 转发规则视图（对齐 Gateway workspace 级 `TunnelDto`）。[secret] 仅创建响应里有明文，列表为 null。
class TunnelSummary {
  TunnelSummary({
    required this.tunnelId,
    required this.localPort,
    required this.remoteAddress,
    required this.remotePort,
    required this.url,
    required this.expiresAtUtc,
    this.name,
    this.secret,
    this.portOpen = true,
    this.running = true,
  });

  final String tunnelId;

  /// 规则名称（可选）。
  final String? name;

  /// 访问入口端口标识。
  final int localPort;

  /// Worker 侧目标地址（默认 127.0.0.1）。
  final String remoteAddress;

  /// Worker 侧目标端口。旧字段 `port` 与之同值。
  final int remotePort;

  final String url;
  final String? secret;
  final DateTime expiresAtUtc;

  /// 创建响应带回：远端服务当前是否可达（false = 服务未启动，等它就绪即生效）。
  final bool portOpen;

  /// 创建即运行；撤销后规则不存在。
  final bool running;

  bool get hasAccessKey =>
      Uri.tryParse(url)?.queryParameters['k']?.isNotEmpty == true;

  TunnelSummary withUrl(String value) => TunnelSummary(
    tunnelId: tunnelId,
    localPort: localPort,
    remoteAddress: remoteAddress,
    remotePort: remotePort,
    url: value,
    expiresAtUtc: expiresAtUtc,
    name: name,
    secret: secret,
    portOpen: portOpen,
    running: running,
  );

  factory TunnelSummary.fromJson(Map<String, dynamic> json) => TunnelSummary(
    // 字段全兜底（对齐 ArkTS mapTunnel）：网关个别字段缺失时不应崩。
    tunnelId: json['tunnelId'] as String? ?? '',
    name: json['name'] as String?,
    localPort: (json['localPort'] as num?)?.toInt() ?? 0,
    remoteAddress: json['remoteAddress'] as String? ?? '127.0.0.1',
    remotePort:
        (json['remotePort'] as num?)?.toInt() ??
        (json['port'] as num?)?.toInt() ??
        0,
    url: json['url'] as String? ?? '',
    secret: json['secret'] as String?,
    expiresAtUtc:
        DateTime.tryParse(json['expiresAtUtc'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    portOpen: json['portOpen'] as bool? ?? true,
    running: json['running'] as bool? ?? true,
  );
}

/// Workspace 端口转发数据源（design/06：规则归属 Workspace）。
class TunnelRepository {
  TunnelRepository(this._client, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _client;
  final FlutterSecureStorage _storage;

  String _key(String id) {
    final identity = base64Url.encode(
      utf8.encode(
        '${_client.baseUrl}|${_client.tokenStore.username ?? ''}|$id',
      ),
    );
    return 'tunnel.access.$identity';
  }

  Future<TunnelSummary> _withAccess(TunnelSummary tunnel) async {
    if (tunnel.hasAccessKey) {
      await _storage.write(key: _key(tunnel.tunnelId), value: tunnel.url);
      return tunnel;
    }
    final cached = await _storage.read(key: _key(tunnel.tunnelId));
    final secret = cached == null
        ? null
        : Uri.tryParse(cached)?.queryParameters['k'];
    if (secret == null || secret.isEmpty) return tunnel;
    final current = Uri.parse(tunnel.url);
    return tunnel.withUrl(
      current
          .replace(queryParameters: {...current.queryParameters, 'k': secret})
          .toString(),
    );
  }

  /// 列出 workspace 的转发规则。响应为 TunnelListResponse：{tunnels: [...]}。
  Future<List<TunnelSummary>> list(String workspaceId) async {
    try {
      final json = await _client.getMap(
        '/api/me/workspaces/$workspaceId/tunnels',
      );
      final items = (json['tunnels'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(TunnelSummary.fromJson)
          .toList();
      return await Future.wait(items.map(_withAccess));
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<TunnelSummary> create({
    required String workspaceId,
    String? name,
    required int localPort,
    String? remoteAddress,
    required int remotePort,
  }) async {
    try {
      final json = await _client.postMap(
        '/api/me/workspaces/$workspaceId/tunnels',
        {
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          'localPort': localPort,
          if (remoteAddress != null && remoteAddress.trim().isNotEmpty)
            'remoteAddress': remoteAddress.trim(),
          'remotePort': remotePort,
        },
      );
      return await _withAccess(TunnelSummary.fromJson(json));
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<TunnelSummary> update({
    required String workspaceId,
    required String tunnelId,
    String? name,
    int? localPort,
    String? remoteAddress,
    int? remotePort,
  }) async {
    try {
      final json = await _client.patch(
        '/api/me/workspaces/$workspaceId/tunnels/$tunnelId',
        {
          'name': ?name?.trim(),
          'localPort': localPort,
          'remoteAddress': ?remoteAddress?.trim(),
          'remotePort': ?remotePort,
        },
      );
      return await _withAccess(TunnelSummary.fromJson(json));
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<void> revoke(String tunnelId) async {
    try {
      await _client.delete('/api/me/tunnels/$tunnelId');
      await _storage.delete(key: _key(tunnelId));
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }
}

final tunnelRepositoryProvider = Provider<TunnelRepository>(
  (ref) => TunnelRepository(ref.watch(apiClientProvider)),
);
