import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/session.dart';
import '../../../core/models/worker.dart';
import '../../../core/storage/app_preferences.dart';


class WorkerDetail {
  const WorkerDetail({required this.worker, required this.sessions});

  final WorkerSummary worker;
  final List<SessionSummary> sessions;

  factory WorkerDetail.fromJson(Map<String, dynamic> json) => WorkerDetail(
        worker: WorkerSummary.fromJson(json),
        sessions: ((json['sessions'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SessionSummary.fromJson)
            .toList(),
      );
}

class UpgradeWorkerResult {
  const UpgradeWorkerResult({required this.message, this.targetVersion});

  final String message;
  final String? targetVersion;
}

/// 网关公告（字段对齐 ArkTS AnnouncementInfo）。
class GatewayAnnouncement {
  const GatewayAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.url,
  });

  final String id;
  final String title;
  final String body;
  final String buttonLabel;
  final String url;

  factory GatewayAnnouncement.fromJson(Map<String, dynamic> json) =>
      GatewayAnnouncement(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        buttonLabel: json['buttonLabel'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

/// Session 数据源（对齐 Gateway `/api/sessions` 与 `/api/me/sessions*`）。
class SessionRepository {
  SessionRepository(this._client, this._prefs);

  final ApiClient _client;
  final AppPreferences _prefs;

  Future<List<SessionSummary>> list() async {
    final raw = await _client.getList('/api/me/sessions');
    return raw.cast<Map<String, dynamic>>().map(SessionSummary.fromJson).toList();
  }

  /// 网关公告（对齐 ArkTS GET /api/announcements，首页弹窗用）。
  Future<List<GatewayAnnouncement>> announcements() async {
    final raw = await _client.getList('/api/announcements');
    return raw.cast<Map<String, dynamic>>().map(GatewayAnnouncement.fromJson).toList();
  }

  Future<List<WorkerSummary>> workers() async {
    final raw = await _client.getList('/api/me/workers');
    return raw.cast<Map<String, dynamic>>().map(WorkerSummary.fromJson).toList();
  }

  Future<GatewayInfo> gatewayInfo() async {
    return GatewayInfo.fromJson(await _client.getMap('/api/gateway/info'));
  }

  /// Worker 详情（含宿主会话列表）。
  Future<WorkerDetail> workerDetail(String workerId) async {
    final json = await _client.getMap('/api/me/workers/$workerId');
    return WorkerDetail.fromJson(json);
  }

  /// 触发 Worker 自升级。Gateway 返回 {message, targetVersion?}。
  Future<UpgradeWorkerResult> upgradeWorker(String workerId) async {
    final json = await _client.postMap('/api/me/workers/$workerId/upgrade', {});
    return UpgradeWorkerResult(
      message: json['message'] as String? ?? '',
      targetVersion: json['targetVersion'] as String?,
    );
  }

  /// 创建 shell 会话。`clientRequestId` 幂等键，防重复点击造成双开。
  Future<SessionSummary> create({required int columns, required int rows, String? workerId}) async {
    Map<String, dynamic> json;
    try {
      json = await _client.postMap('/api/sessions', {
        'runtime': 'shell',
        'columns': columns,
        'rows': rows,
        'clientRequestId': _newRequestId(),
        'workerId': ?workerId,
      });
    } on ApiException {
      rethrow;
    }
    final sessionId = json['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw ApiException(0, serverMessage: 'create session returned no sessionId');
    }
    final worker = json['workerId'] as String? ?? workerId ?? '';
    return SessionSummary(
      sessionId: sessionId,
      name: '',
      workerId: worker,
      status: SessionStatus.detachedGracePeriod,
      createdAt: DateTime.now().toUtc(),
      lastActivityAt: DateTime.now().toUtc(),
    );
  }

  Future<void> rename({required String sessionId, required String name}) async {
    try {
      // 网关只实现了 PUT（对齐 ArkTS renameSession），PATCH 会 405。
      await _client.putMap('/api/me/sessions/$sessionId', {'name': name});
    } on ApiException {
      rethrow;
    }
  }

  /// 终止远程会话（PTY kill）。Gateway 返回 202 Accepted。
  Future<void> terminate({required String sessionId}) async {
    try {
      await _client.postMap('/api/me/sessions/$sessionId/terminate', null);
    } on ApiException {
      rethrow;
    }
  }

  /// 删除会话记录（仅在会话已结束后可用）。
  Future<void> delete({required String sessionId}) async {
    try {
      await _client.delete('/api/me/sessions/$sessionId');
    } on ApiException {
      rethrow;
    }
  }

  Future<void> rememberCurrent(String? sessionId) => _prefs.setLastSessionId(sessionId);

  static int _requestCounter = 0;

  /// 幂等键：时间戳 + 自增序号，同进程内唯一。
  String _newRequestId() {
    _requestCounter++;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$_requestCounter';
  }
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(
    ref.watch(apiClientProvider),
    ref.watch(appPreferencesProvider),
  );
});
