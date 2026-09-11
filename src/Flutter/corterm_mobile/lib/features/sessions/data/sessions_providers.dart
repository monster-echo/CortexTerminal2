import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/session.dart';
import '../../../core/models/worker.dart';
import 'session_repository.dart';

/// 会话列表。invalidate 后重新拉取（pull-to-refresh、生命周期事件均会触发）。
final sessionsProvider = FutureProvider<List<SessionSummary>>((ref) {
  return ref.watch(sessionRepositoryProvider).list();
});

final workersProvider = FutureProvider<List<WorkerSummary>>((ref) {
  return ref.watch(sessionRepositoryProvider).workers();
});

final gatewayInfoProvider = FutureProvider<GatewayInfo>((ref) {
  return ref.watch(sessionRepositoryProvider).gatewayInfo();
});

/// 按 RUNNING / RECENT 分组（§15）：RUNNING = 进程仍存活，RECENT = 按最近活动排序的已结束会话。
class SessionGroups {
  const SessionGroups({required this.running, required this.recent});

  final List<SessionSummary> running;
  final List<SessionSummary> recent;
}

final sessionGroupsProvider = Provider<SessionGroups>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const <SessionSummary>[];
  final running = sessions.where((s) => s.status.isRunning).toList()
    ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
  final recent = sessions.where((s) => !s.status.isRunning).toList()
    ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
  return SessionGroups(running: running, recent: recent);
});

/// HOME 用：运行中 + 最近（最多 5 条）。
final homeOverviewProvider = Provider<SessionGroups>((ref) {
  final groups = ref.watch(sessionGroupsProvider);
  return SessionGroups(
    running: groups.running,
    recent: groups.recent.take(5).toList(),
  );
});
