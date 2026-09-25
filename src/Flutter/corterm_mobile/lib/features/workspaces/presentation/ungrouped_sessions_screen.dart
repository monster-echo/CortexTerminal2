import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../../core/models/session.dart';
import '../../sessions/data/session_repository.dart';
import '../../sessions/data/sessions_providers.dart';
import '../data/workspace_providers.dart';

/// 未分组会话页：所有未关联工作区的会话集中在这里，
/// 支持把会话移动到任意工作区（design/00 核心模型：会话必须归属工作区）。
class UngroupedSessionsScreen extends ConsumerWidget {
  const UngroupedSessionsScreen({super.key});

  Future<void> _moveToWorkspace(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
  ) async {
    final workspaces = ref.read(workspacesProvider).value ?? const [];
    final target = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colorsOf(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        final colors = colorsOf(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('移动到工作区',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary)),
              ),
              if (workspaces.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('还没有工作区，先创建一个吧',
                      style:
                          TextStyle(fontSize: 14, color: colors.textSecondary)),
                ),
              for (final w in workspaces)
                InkWell(
                  onTap: () => Navigator.pop(sheetContext, w.workspaceId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Text(w.displayName,
                        style: TextStyle(
                            fontSize: 16, color: colors.textPrimary)),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (target == null || target.isEmpty) return;

    await ref
        .read(sessionRepositoryProvider)
        .moveSessionWorkspace(sessionId: sessionId, workspaceId: target);
    ref.invalidate(sessionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = colorsOf(context);
    final sessions = ref.watch(ungroupedSessionsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('未分组会话 (${sessions.length})',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary)),
      ),
      body: sessions.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_outlined, message: '没有未分组的会话')
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(sessionsProvider),
              child: ListView(
                children: [
                  for (final s in sessions)
                    ListRow(
                      title: s.displayName,
                      subtitle:
                          '${s.workerName ?? s.workerId} · ${s.status.isAlive ? '运行中' : '已结束'}',
                      leading: Icon(Icons.terminal_outlined,
                          color: colors.textSecondary),
                      trailing: IconButton(
                        tooltip: '移动到工作区',
                        icon: Icon(Icons.drive_file_move_outline,
                            size: 20, color: colors.textSecondary),
                        onPressed: () =>
                            _moveToWorkspace(context, ref, s.sessionId),
                      ),
                      onTap: () => context.push('/sessions/${s.sessionId}'),
                    ),
                ],
              ),
            ),
    );
  }
}
