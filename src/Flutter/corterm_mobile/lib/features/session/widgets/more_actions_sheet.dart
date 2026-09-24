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
import '../session_controller.dart';
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 栈式 modal：子 sheet / 子页面压在本菜单之上，返回即回到菜单，
        // 不先 pop 自己。
        AppRow(
          icon: LucideIcons.info,
          label: l10n.sessionDetails,
          onTap: () =>
              SessionDetailsSheet.show(context, sessionId: sessionId),
        ),
        AppRow(
          icon: LucideIcons.folder,
          label: l10n.filesTitle,
          onTap: () => context.push('/files/$sessionId'),
        ),
        AppRow(
          icon: LucideIcons.arrowLeftRight,
          label: l10n.tunnelTitle,
          onTap: () => PortForwardingSheet.show(context, sessionId: sessionId),
        ),
        Divider(color: scheme.border, indent: 16, endIndent: 16),
        AppRow(
          icon: LucideIcons.trash2,
          label: l10n.terminateSession,
          destructive: canTerminate,
          onTap: canTerminate ? () => _terminate(context, ref) : null,
        ),
      ],
    );
  }

  /// Terminate 必须确认（§28），且只在该动作明确点击后执行（§27）。
  /// 确认框压在菜单上方；终止成功后连菜单一起关闭。
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
      await ref.read(sessionControllerProvider.notifier).closeTerminal(sessionId);
    }
    // 会话已不存在，回到菜单没有意义——整个菜单一并关闭。
    if (context.mounted) Navigator.of(context).pop();
  }
}
