import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../sessions/data/sessions_providers.dart';
import '../session_controller.dart';

/// Session Details（§54/§23）：会话元信息速览（不含 sessionId 与重命名入口）。
class SessionDetailsSheet extends ConsumerStatefulWidget {
  const SessionDetailsSheet({super.key, required this.sessionId});

  final String sessionId;

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
  }) {
    return showCortermSheet(
      context: context,
      builder: (_) => SessionDetailsSheet(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<SessionDetailsSheet> createState() => _SessionDetailsSheetState();
}

class _SessionDetailsSheetState extends ConsumerState<SessionDetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionsProvider).value
        ?.where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;

    if (session == null) {
      return const SizedBox(height: 120);
    }

    final statusLabel = switch (session.status) {
      SessionStatus.attached => l10n.statusAttached,
      SessionStatus.detachedGracePeriod => l10n.statusDetachedGracePeriod,
      SessionStatus.recovering => l10n.statusRecovering,
      SessionStatus.exited => l10n.statusExited,
      SessionStatus.expired => l10n.statusExpired,
    };

    // 终端尺寸与延迟取自当前附着（对齐 MAUI 会话详情 ActionSheet）。
    final wsEntry = ref.watch(sessionControllerProvider).entryOf(session.sessionId);
    final rows = <(String, String)>[
      (l10n.agentKind, session.agentKind.label),
      (l10n.worker, session.workerName ?? session.workerId),
      (l10n.connection, statusLabel),
      if (wsEntry != null)
        (l10n.terminalSize, '${wsEntry.terminal.viewWidth} × ${wsEntry.terminal.viewHeight}'),
      if (wsEntry?.rttMs != null) (l10n.latency, '${wsEntry!.rttMs} ms'),
      (l10n.createdAt, _fmt(session.createdAt)),
      (l10n.lastActivity, _fmt(session.lastActivityAt)),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.displayName,
                    style: theme.textTheme.large.copyWith(color: scheme.foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Divider(height: 20, color: scheme.border),
            for (final (label, value) in rows)
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
        ),
      ),
    );
  }

  String _fmt(DateTime t) {
    final local = t.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
