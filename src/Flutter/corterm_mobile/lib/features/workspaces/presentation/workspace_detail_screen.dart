import '../../../shared/layout/adaptive_sheet.dart';
import '../../../shared/layout/adaptive_page_scaffold.dart';
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
  bool _creatingSession = false;

  Future<void> _createSession(Workspace workspace) async {
    if (_creatingSession) return;
    setState(() => _creatingSession = true);
    try {
      final session = await ref
          .read(sessionRepositoryProvider)
          .create(
            columns: 80,
            rows: 24,
            workerId: workspace.workerId,
            workspaceId: workspace.workspaceId,
          );
      if (!mounted) return;
      ref.invalidate(sessionsProvider);
      await context.push('/sessions/${session.sessionId}');
      if (mounted) ref.invalidate(sessionsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _creatingSession = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(workspacesProvider);
    ref.invalidate(workersProvider);
    ref.invalidate(sessionsProvider);
    try {
      await Future.wait([
        ref.read(workspacesProvider.future),
        ref.read(workersProvider.future),
        ref.read(sessionsProvider.future),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String get workspaceId => widget.workspaceId;

  Future<void> _confirmMoveOut(SessionSummary session) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final confirmed = await showCortermDialog<bool>(
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

    return AdaptivePageScaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(workspace?.displayName ?? ''),
        actions: [
          PopupMenuButton<String>(
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            icon: const Icon(Icons.more_horiz),
            enabled: workspace != null,
            onSelected: (action) {
              final selected = workspace;
              if (selected == null) return;
              if (action == 'files') {
                context.push(
                  '/workspaces/$workspaceId/files?name=${Uri.encodeComponent(selected.displayName)}&root=${Uri.encodeComponent(selected.rootPath ?? '')}',
                );
              } else if (action == 'tunnels') {
                context.push('/workspaces/$workspaceId/tunnels');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'files',
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(l10n.files),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'tunnels',
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, size: 20),
                    const SizedBox(width: 12),
                    Text(l10n.portForwardingTitle),
                  ],
                ),
              ),
            ],
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
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
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
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.sessions,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
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
                      title:
                          Localizations.localeOf(context).languageCode == 'zh'
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
                      margin: const EdgeInsets.only(bottom: 8),
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
                            padding: const EdgeInsets.all(16),
                            constraints: const BoxConstraints(minHeight: 80),
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
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        relativeTime(
                                          s.lastActivityAt,
                                          languageCode: Localizations.localeOf(
                                            context,
                                          ).languageCode,
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: s.status.isAlive
                                          ? colors.success
                                          : colors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s.status.isAlive
                                          ? l10n.sessionRunning
                                          : l10n.sessionEnded,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                      child: Text(
                        l10n.noSessions,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  if (sessions.isNotEmpty)
                    Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '左滑删除会话，长按移出工作区'
                          : 'Swipe left to delete; long press to move out',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: workspace == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: FilledButton.icon(
                  onPressed: _creatingSession || !online
                      ? null
                      : () => _createSession(workspace),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: colors.emphasis,
                    foregroundColor: colors.onEmphasis,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _creatingSession
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add, size: 20),
                  label: Text(l10n.newSession),
                ),
              ),
            ),
    );
  }
}
