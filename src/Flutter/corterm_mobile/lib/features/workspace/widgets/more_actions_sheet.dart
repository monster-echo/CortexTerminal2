import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../shared/widgets/list_group.dart';

import '../../../core/models/session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../sessions/data/session_repository.dart';
import '../../tunnels/presentation/port_forwarding_sheet.dart';
import '../workspace_controller.dart';
import 'session_details_sheet.dart';

/// More Menu（§25/§26）：Session Details / All Sessions / Settings + 底部危险区 Terminate。
class MoreActionsSheet extends ConsumerWidget {
  const MoreActionsSheet({super.key, required this.sessionId});

  final String sessionId;

  static Future<void> show(BuildContext context, {required String sessionId}) {
    return showCortermSheet(
      context: context,
      builder: (_) => MoreActionsSheet(sessionId: sessionId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final sessions = ref.watch(sessionsProvider);
    final session = sessions.value?.where((s) => s.sessionId == sessionId).firstOrNull;
    final canTerminate = session?.status.isAlive ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
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
              icon: LucideIcons.folder,
              label: l10n.filesTitle,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/files/$sessionId');
              },
            ),
            AppRow(
              icon: LucideIcons.arrowLeftRight,
              label: l10n.tunnelTitle,
              onTap: () {
                Navigator.of(context).pop();
                PortForwardingSheet.show(context, sessionId: sessionId);
              },
            ),
            AppRow(
              icon: LucideIcons.layoutGrid,
              label: l10n.allSessions,
              onTap: () {
                Navigator.of(context).pop();
                context.go('/sessions');
              },
            ),
            AppRow(
              icon: LucideIcons.settings,
              label: l10n.settings,
              onTap: () {
                Navigator.of(context).pop();
                context.go('/settings');
              },
            ),
            Divider(color: scheme.border, indent: 16, endIndent: 16),
            AppRow(
              icon: LucideIcons.trash2,
              label: l10n.terminateSession,
              destructive: canTerminate,
              onTap: canTerminate
                  ? () {
                      Navigator.of(context).pop();
                      _terminate(context, ref);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Terminate 必须确认（§28），且只在该动作明确点击后执行（§27）。
  Future<void> _terminate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.read(sessionsProvider).value ?? const [];
    final session = sessions.where((s) => s.sessionId == sessionId).firstOrNull;
    final name = session?.displayName ?? l10n.terminal;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.terminateConfirmTitle(name),
      body: l10n.terminateConfirmBody,
      confirmLabel: l10n.terminate,
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(sessionRepositoryProvider).terminate(sessionId: sessionId);
    ref.invalidate(sessionsProvider);
    // 终止后关闭本地终端视图（PTY 已被 kill）。
    if (context.mounted) {
      await ref.read(workspaceControllerProvider.notifier).closeTerminal(sessionId);
    }
  }
}
