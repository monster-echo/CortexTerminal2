import '../../../shared/layout/adaptive_sheet.dart';
import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/relative_time.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../../shared/widgets/swipe_delete.dart';
import '../../../shared/widgets/states.dart' show ErrorState, showAppToast;
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
    final l10n = AppLocalizations.of(context)!;
    final workspaces = await ref.read(workspacesProvider.future);
    if (!context.mounted) return;
    final session = ref
        .read(sessionsProvider)
        .valueOrNull
        ?.where((s) => s.sessionId == sessionId)
        .firstOrNull;
    final compatible = workspaces
        .where((workspace) => workspace.workerId == session?.workerId)
        .toList();
    final target = await showAdaptiveModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
      ),
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
                child: Text(
                  l10n.moveToWorkspace,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (compatible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.workspaceCreatePrompt,
                    style: TextStyle(fontSize: 14, color: colors.textSecondary),
                  ),
                ),
              for (final w in compatible)
                InkWell(
                  onTap: () => Navigator.pop(sheetContext, w.workspaceId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Text(
                      w.displayName,
                      style: TextStyle(fontSize: 16, color: colors.textPrimary),
                    ),
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
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(sessionsProvider);
    final sessions = ref.watch(ungroupedSessionsProvider);

    return AdaptivePageScaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '${l10n.ungroupedSessions} (${sessions.length})',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.hasError
          ? ErrorState(
              message: '${state.error}',
              onRetry: () => ref.invalidate(sessionsProvider),
            )
          : sessions.isEmpty
          ? EmptyState(icon: Icons.inbox_outlined, message: l10n.ungroupedEmpty)
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(sessionsProvider);
                await ref.read(sessionsProvider.future);
              },
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '这里是尚未关联工作区的会话。可将会话移入同一台电脑上的工作区，会话本身会保留。'
                          : 'These sessions have no workspace. Move them to a workspace on the same computer without deleting the session.',
                    ),
                  ),
                  for (final s in sessions)
                    SwipeDelete(
                      key: ValueKey(s.sessionId),
                      title: l10n.deleteSession,
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
                      child: ListRow(
                        title: s.displayName,
                        subtitle:
                            '${s.workerName ?? s.workerId} · ${s.status.isAlive ? l10n.sessionRunning : l10n.sessionEnded} · ${relativeTime(s.lastActivityAt, languageCode: Localizations.localeOf(context).languageCode)}',
                        leading: Icon(
                          Icons.terminal_outlined,
                          color: colors.textSecondary,
                        ),
                        trailing: IconButton(
                          tooltip: l10n.moveToWorkspace,
                          icon: Icon(
                            Icons.drive_file_move_outline,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                          onPressed: () async {
                            try {
                              await _moveToWorkspace(context, ref, s.sessionId);
                            } catch (error) {
                              if (context.mounted) {
                                showAppToast(
                                  context,
                                  '$error',
                                  destructive: true,
                                );
                              }
                            }
                          },
                        ),
                        onTap: () async {
                          await context.push('/sessions/${s.sessionId}');
                          if (context.mounted) ref.invalidate(sessionsProvider);
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
