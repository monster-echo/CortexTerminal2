import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/swipe_delete.dart';
import '../../sessions/data/session_repository.dart';
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

  Future<void> _confirmMoveOut(SessionSummary session) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(zh ? '移出工作区' : 'Move out of workspace'),
        content: Text(
          zh
              ? '把「${session.displayName}」移出工作区？会话不会被删除。'
              : 'Move "${session.displayName}" out of this workspace? The session will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(zh ? '移出' : 'Move out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(sessionRepositoryProvider)
          .moveSessionWorkspace(sessionId: session.sessionId, workspaceId: '');
      ref.invalidate(sessionsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final wsAsync = ref.watch(workspacesProvider);
    var workspace = (wsAsync.asData?.value ?? const <Workspace>[])
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull;
    // 自愈：刚创建后缓存可能尚未包含本工作区（如热恢复/竞态），失效重取一次。
    if (wsAsync.hasValue && workspace == null && !_revalidated) {
      _revalidated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.invalidate(workspacesProvider);
      });
    }
    final sessionsState = ref.watch(sessionsProvider);
    final sessions = ref.watch(workspaceSessionsProvider(workspaceId));
    final workers = ref.watch(workersProvider).asData?.value ?? const [];
    final workerName = workspace == null
        ? null
        : workers
              .where((w) => w.workerId == workspace.workerId)
              .map((w) => w.displayName)
              .firstOrNull;
    final online =
        workspace != null &&
        workers.any((w) => w.workerId == workspace.workerId && w.isOnline);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(workspace?.displayName ?? ''),
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
                    child: Text(
                      l10n.workspaceMissing,
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: online
                                ? colors.success
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${workerName ?? workspace.workerId} · ${online ? l10n.workerOnline : l10n.workerOffline}',
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (workspace.rootPath != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          workspace.rootPath!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _WorkspaceActionRow(
                  icon: Icons.folder_outlined,
                  title: l10n.files,
                  onTap: () => context.push(
                    '/workspaces/$workspaceId/files?name=${Uri.encodeComponent(workspace.displayName)}&root=${Uri.encodeComponent(workspace.rootPath ?? '')}',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.sessions,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        l10n.sessionCount(sessions.length),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (sessionsState.isLoading) const LinearProgressIndicator(),
                if (sessionsState.hasError)
                  TextButton(
                    onPressed: () => ref.invalidate(sessionsProvider),
                    child: Text(l10n.sessionsLoadRetry),
                  ),
                for (final s in sessions)
                  SwipeDelete(
                    key: ValueKey('session-${s.sessionId}'),
                    title: Localizations.localeOf(context).languageCode == 'zh'
                        ? '删除会话'
                        : 'Delete session',
                    message:
                        Localizations.localeOf(context).languageCode == 'zh'
                        ? '删除「${s.displayName}」？此操作不可撤销。'
                        : 'Delete "${s.displayName}"? This cannot be undone.',
                    onDelete: () async {
                      await ref
                          .read(sessionRepositoryProvider)
                          .delete(sessionId: s.sessionId);
                      ref.invalidate(sessionsProvider);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: colors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            await context.push('/sessions/${s.sessionId}');
                            if (mounted) ref.invalidate(sessionsProvider);
                          },
                          onLongPress: () => _confirmMoveOut(s),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.divider),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.terminal_rounded,
                                  size: 22,
                                  color: colors.textPrimary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${s.status.isRunning ? l10n.sessionRunning : l10n.sessionEnded} · ${relativeTime(s.lastActivityAt, languageCode: Localizations.localeOf(context).languageCode)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: colors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (sessions.isEmpty &&
                    !sessionsState.isLoading &&
                    !sessionsState.hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: EmptyState(
                      icon: Icons.terminal,
                      message: l10n.noSessions,
                    ),
                  ),
                ListRow(
                  title: l10n.portForwardingTitle,
                  leading: const Icon(Icons.swap_horiz),
                  onTap: () => context.push('/workspaces/$workspaceId/tunnels'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                ),
              ],
            ),
      bottomNavigationBar: workspace == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () async {
                    await context.push(
                      '/sessions/new?workspaceId=$workspaceId',
                    );
                    if (mounted) ref.invalidate(sessionsProvider);
                  },
                  icon: const Icon(Icons.add),
                  label: Text(l10n.newSession),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.emphasis,
                    foregroundColor: colors.onEmphasis,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
    );
  }
}

class _WorkspaceActionRow extends StatelessWidget {
  const _WorkspaceActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return Material(
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15, color: colors.textPrimary),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
