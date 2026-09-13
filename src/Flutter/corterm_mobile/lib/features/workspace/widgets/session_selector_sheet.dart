import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../sessions/data/sessions_providers.dart';
import 'new_session_sheet.dart';
import '../workspace_controller.dart';
import 'session_list_item.dart';

/// Session Selector（§10/§11）：Modal Bottom Sheet，快速切换，RUNNING / RECENT 分组。
/// 不离开 Terminal 页面即可切换；点击 ＋ 打开 New Session Sheet。
class SessionSelectorSheet extends ConsumerWidget {
  const SessionSelectorSheet({super.key, required this.currentSessionId});

  final String? currentSessionId;

  static Future<void> show(BuildContext context, {required String? currentSessionId}) {
    return showCortermSheet(
      context: context,
      builder: (_) => SessionSelectorSheet(currentSessionId: currentSessionId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ref.watch(sessionGroupsProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.sessions,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ShadTheme.of(context).colorScheme.foreground,
                    ),
                  ),
                ),
                ShadIconButton(
                  icon: const Icon(LucideIcons.plus),
                  onPressed: () {
                    Navigator.of(context).pop();
                    showNewSessionSheet(context, onCreated: controller.open);
                  },
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                if (groups.running.isNotEmpty) ...[
                  SheetSectionHeader(label: l10n.groupActive),
                  for (final s in groups.running)
                    SessionListItem(
                      session: s,
                      isCurrent: s.sessionId == currentSessionId,
                      onTap: () {
                        Navigator.of(context).pop();
                        if (s.sessionId != currentSessionId) {
                          controller.open(s.sessionId);
                        }
                      },
                    ),
                ],
                if (groups.recent.isNotEmpty) ...[
                  SheetSectionHeader(label: l10n.groupEnded),
                  for (final s in groups.recent.take(10))
                    SessionListItem(
                      session: s,
                      isCurrent: s.sessionId == currentSessionId,
                      onTap: () {
                        Navigator.of(context).pop();
                        if (s.sessionId != currentSessionId) {
                          controller.open(s.sessionId);
                        }
                      },
                    ),
                ],
                if (groups.running.isEmpty && groups.recent.isEmpty)
                  SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        l10n.noSessions,
                        style: TextStyle(
                          fontSize: 14,
                          color: ShadTheme.of(context).colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: ShadButton.outline(
              leading: const Icon(LucideIcons.plus, size: 18),
              onPressed: () {
                Navigator.of(context).pop();
                showNewSessionSheet(context, onCreated: controller.open);
              },
              child: Text(l10n.newSession),
            ),
          ),
        ],
      ),
    );
  }
}
