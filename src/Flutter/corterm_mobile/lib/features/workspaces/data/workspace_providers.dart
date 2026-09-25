import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/session.dart';
import '../../../core/models/workspace.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../workers/data/workspace_repository.dart';

/// 全部工作区（默认工作区在前，其余按名称排序）。
final workspacesProvider = FutureProvider<List<Workspace>>((ref) async {
  final list = await ref.watch(workspaceRepositoryProvider).list();
  return list..sort((a, b) {
    if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
    return a.name.compareTo(b.name);
  });
});

/// 未分组会话（未关联任何工作区）。
final ungroupedSessionsProvider = Provider<List<SessionSummary>>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const <SessionSummary>[];
  return sessions
      .where((s) => s.workspaceId.isEmpty)
      .toList()
    ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
});

/// 某个工作区下的 Session（按最近活动倒序）。
final workspaceSessionsProvider =
    Provider.family<List<SessionSummary>, String>((ref, workspaceId) {
  final sessions = ref.watch(sessionsProvider).value ?? const <SessionSummary>[];
  return sessions
      .where((s) => s.workspaceId == workspaceId)
      .toList()
    ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
});
