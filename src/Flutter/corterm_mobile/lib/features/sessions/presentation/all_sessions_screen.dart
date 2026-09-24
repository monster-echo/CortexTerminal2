import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/install_prompt.dart';
import '../../../shared/widgets/list_group.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../data/sessions_providers.dart';
import '../data/session_repository.dart';
import '../../session/widgets/new_session_sheet.dart';
import '../../session/widgets/session_list_item.dart';
import '../../session/widgets/session_details_sheet.dart';
import '../../session/session_controller.dart';

/// All Sessions（§45/§46）：完整管理页（区别于快速切换的 Selector）。
/// 支持重命名 / 详情 / 终止 / 删除。
class AllSessionsScreen extends ConsumerWidget {
  const AllSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ref.watch(sessionGroupsProvider);

    final scheme = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        title: l10n.allSessions,
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          ShadIconButton.ghost(
            foregroundColor: scheme.foreground,
            icon: const Icon(LucideIcons.plus),
            onPressed: () => showNewSessionSheet(
              context,
              onCreated: (sessionId) {
                ref.read(sessionControllerProvider.notifier).open(sessionId);
                context.go('/workspace');
              },
            ),
          ),
        ],
      ),
      body: groups.running.isEmpty && groups.recent.isEmpty
          ? ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              children: [
                EmptyState(
                  title: l10n.noSessions,
                  actionLabel: l10n.newSession,
                  onAction: () => showNewSessionSheet(
                    context,
                    onCreated: (sessionId) {
                      ref.read(sessionControllerProvider.notifier).open(sessionId);
                      context.go('/workspace');
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.border),
                  ),
                  child: InstallPromptCard(
                    title: l10n.installWorkerTitle,
                    intro: l10n.installWorkerIntro,
                  ),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(sessionsProvider);
                await ref.read(sessionsProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (groups.running.isNotEmpty) ...[
                    _GroupHeader(l10n.groupActive),
                    for (final s in groups.running)
                      SessionListItem(
                        session: s,
                        isCurrent: false,
                        onTap: () {
                          ref.read(sessionControllerProvider.notifier).open(s.sessionId);
                          context.go('/workspace');
                        },
                        onLongPress: () => _showActions(context, ref, s.sessionId, canTerminate: true),
                      ),
                  ],
                  if (groups.recent.isNotEmpty) ...[
                    _GroupHeader(l10n.groupEnded),
                    for (final s in groups.recent)
                      SessionListItem(
                        session: s,
                        onTap: () {
                          ref.read(sessionControllerProvider.notifier).open(s.sessionId);
                          context.go('/workspace');
                        },
                        onLongPress: () => _showActions(context, ref, s.sessionId, canTerminate: false),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref, String sessionId,
      {required bool canTerminate}) {
    final l10n = AppLocalizations.of(context)!;
    showCortermSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppRow(
                icon: LucideIcons.info,
                label: l10n.sessionDetails,
                onTap: () {
                  Navigator.of(context).pop();
                  SessionDetailsSheet.show(context, sessionId: sessionId);
                },
              ),
              AppRow(
                icon: LucideIcons.squarePen,
                label: l10n.rename,
                onTap: () {
                  Navigator.of(context).pop();
                  _rename(context, ref, sessionId);
                },
              ),
              AppRow(
                icon: LucideIcons.trash2,
                label: canTerminate ? l10n.terminateSession : l10n.deleteSession,
                destructive: true,
                onTap: () {
                  Navigator.of(context).pop();
                  if (canTerminate) {
                    _terminate(context, ref, sessionId);
                  } else {
                    _delete(context, ref, sessionId);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, String sessionId) async {
    final l10n = AppLocalizations.of(context)!;
    final session = ref
        .read(sessionsProvider)
        .value!
        .where((s) => s.sessionId == sessionId)
        .first;
    final controller = TextEditingController(text: session.name);
    final name = await showCortermSheetDialog<String>(
      context: context,
      title: l10n.sessionRenameTitle,
      child: ShadInputFormField(
        controller: controller,
        label: Text(l10n.sessionNameLabel),
        placeholder: Text(l10n.sessionNameLabel),
        maxLength: 100,
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ShadButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(l10n.save),
        ),
      ],
    );
    if (name == null) return;
    await ref.read(sessionRepositoryProvider).rename(sessionId: sessionId, name: name);
    ref.invalidate(sessionsProvider);
  }

  Future<void> _terminate(BuildContext context, WidgetRef ref, String sessionId) async {
    final l10n = AppLocalizations.of(context)!;
    final session = ref
        .read(sessionsProvider)
        .value!
        .where((s) => s.sessionId == sessionId)
        .first;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.terminateConfirmTitle(session.displayName),
      body: l10n.terminateConfirmBody,
      confirmLabel: l10n.terminate,
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(sessionRepositoryProvider).terminate(sessionId: sessionId);
    ref.invalidate(sessionsProvider);
    if (context.mounted) {
      await ref.read(sessionControllerProvider.notifier).closeTerminal(sessionId);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String sessionId) async {
    final l10n = AppLocalizations.of(context)!;
    final session = ref
        .read(sessionsProvider)
        .value!
        .where((s) => s.sessionId == sessionId)
        .first;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.deleteSessionConfirmTitle(session.displayName),
      body: l10n.deleteSessionConfirmBody,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(sessionRepositoryProvider).delete(sessionId: sessionId);
    ref.invalidate(sessionsProvider);
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: theme.textTheme.small.copyWith(
          color: theme.colorScheme.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
