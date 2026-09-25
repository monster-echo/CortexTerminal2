import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/session.dart';
import '../../../core/models/workspace.dart';
import '../../../shared/utils/relative_time.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../sessions/data/sessions_providers.dart';
import '../data/workspace_providers.dart';

/// 工作区详情（design/01 §5）：名称 + 电脑/路径 + Session 列表 + 操作入口。
class WorkspaceDetailScreen extends ConsumerStatefulWidget {
  const WorkspaceDetailScreen({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceDetailScreen> createState() =>
      _WorkspaceDetailScreenState();
}

class _WorkspaceDetailScreenState extends ConsumerState<WorkspaceDetailScreen> {
  bool _revalidated = false;

  String get workspaceId => widget.workspaceId;

  @override
  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final wsAsync = ref.watch(workspacesProvider);
    var workspace = (wsAsync.value ?? const <Workspace>[])
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull;
    // 自愈：刚创建后缓存可能尚未包含本工作区（如热恢复/竞态），失效重取一次。
    if (wsAsync.hasValue && workspace == null && !_revalidated) {
      _revalidated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.invalidate(workspacesProvider);
      });
    }
    final sessions = ref.watch(workspaceSessionsProvider(workspaceId));
    final workers = ref.watch(workersProvider).value ?? const [];
    final workerName = workspace == null
        ? null
        : workers
            .where((w) => w.workerId == workspace.workerId)
            .map((w) => w.displayName)
            .firstOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(sessionsProvider),
          ),
        ],
      ),
      body: workspace == null
          ? wsAsync.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: Text('工作区不存在',
                      style: TextStyle(color: colors.textSecondary)))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(workspace.displayName,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('电脑：${workerName ?? workspace.workerId}',
                          style: TextStyle(
                              fontSize: 13, color: colors.textSecondary)),
                      if (workspace.rootPath != null)
                        Text('路径：${workspace.rootPath}',
                            style: TextStyle(
                                fontSize: 13, color: colors.textSecondary)),
                    ],
                  ),
                ),
                SectionHeader('会话'),
                for (final s in sessions)
                  ListRow(
                    title: s.displayName,
                    subtitle: s.status.isRunning
                        ? '运行中 · 最后活跃 ${relativeTime(s.lastActivityAt)}'
                        : '已结束 · ${relativeTime(s.lastActivityAt)}',
                    leading: Icon(Icons.circle,
                        size: 10,
                        color: s.status.isRunning
                            ? colors.success
                            : colors.textSecondary),
                    onTap: () => context.push('/sessions/${s.sessionId}'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                  ),
                if (sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: EmptyState(
                        icon: Icons.terminal, message: '还没有会话'),
                  ),
                SectionHeader('操作'),
                ListRow(
                  title: '新建会话',
                  leading: const Icon(Icons.add),
                  onTap: () =>
                      context.push('/sessions/new?workspaceId=$workspaceId'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                ),
                ListRow(
                  title: '文件',
                  leading: const Icon(Icons.folder),
                  onTap: () => context.push(
                      '/workspaces/$workspaceId/files?name=${Uri.encodeComponent(workspace.displayName)}&root=${Uri.encodeComponent(workspace.rootPath ?? '')}'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                ),
                ListRow(
                  title: '端口转发',
                  leading: const Icon(Icons.swap_horiz),
                  onTap: () => context.push('/workspaces/$workspaceId/tunnels'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                ),
              ],
            ),
    );
  }
}
