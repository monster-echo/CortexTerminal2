import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../features/sessions/data/sessions_providers.dart';
import '../session_state.dart';
import '../../../shared/widgets/connection_status_dot.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../session_controller.dart';
import 'session_status.dart';

/// Connection Details（§20/§21）：点击 AppBar 状态圆点弹出。
/// 展示连接状态 / Worker / Gateway / Latency / Network —— 全部二级信息，不常驻主界面。
class ConnectionDetailsSheet extends ConsumerStatefulWidget {
  const ConnectionDetailsSheet({super.key, required this.sessionId});

  final String sessionId;

  static Future<void> show(BuildContext context, {required String sessionId}) {
    return showCortermSheet(
      context: context,
      builder: (_) => ConnectionDetailsSheet(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<ConnectionDetailsSheet> createState() => _ConnectionDetailsSheetState();
}

class _ConnectionDetailsSheetState extends ConsumerState<ConnectionDetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final ws = ref.watch(sessionControllerProvider);
    final sessions = ref.watch(sessionsProvider);
    final entry = ws.entryOf(widget.sessionId);
    final session = sessions.value?.where((s) => s.sessionId == widget.sessionId).firstOrNull;

    final (dotColor, pulse) = entry == null
        ? (scheme.mutedForeground, false)
        : connDotStyle(scheme, entry.connState);

    final stateText = switch (entry?.connState) {
      TerminalConnState.live => l10n.connLive,
      TerminalConnState.connecting => l10n.connConnecting,
      TerminalConnState.replaying => l10n.connReplaying,
      TerminalConnState.reconnecting => l10n.connReconnecting,
      TerminalConnState.idle => l10n.connIdle,
      TerminalConnState.exited => l10n.connExited,
      TerminalConnState.error => l10n.connError,
      null => l10n.connIdle,
    };

    final rows = <(String, String)>[
      (l10n.worker, session?.workerName ?? session?.workerId ?? '—'),
      (l10n.gateway, entry?.connState == TerminalConnState.live ? l10n.gatewayConnected : l10n.gatewayDisconnected),
      (
        l10n.latency,
        entry?.rttMs != null ? l10n.ms(entry!.rttMs!) : '—',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.connection,
              style: theme.textTheme.large.copyWith(color: scheme.foreground),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ConnectionStatusDot(color: dotColor, size: 10, pulse: pulse),
                const SizedBox(width: 10),
                Text(
                  stateText,
                  style: theme.textTheme.small.copyWith(color: scheme.foreground),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final (label, value) in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        label,
                        style: theme.textTheme.small
                            .copyWith(color: scheme.mutedForeground),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.small.copyWith(
                          fontWeight: FontWeight.w500,
                          color: scheme.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
