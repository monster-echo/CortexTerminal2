import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../sessions/data/session_repository.dart';
import '../workspace_controller.dart';

/// Session Details（§54/§23）：完整元信息，含 sessionId（可复制）与重命名入口。
class SessionDetailsSheet extends ConsumerStatefulWidget {
  const SessionDetailsSheet({super.key, required this.sessionId});

  final String sessionId;

  static Future<void> show(BuildContext context, {required String sessionId}) {
    return showCortermSheet(
      context: context,
      builder: (_) => SessionDetailsSheet(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<SessionDetailsSheet> createState() => _SessionDetailsSheetState();
}

class _SessionDetailsSheetState extends ConsumerState<SessionDetailsSheet> {
  bool _renaming = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
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
    final wsEntry = ref.watch(workspaceControllerProvider).entryOf(session.sessionId);
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ShadIconButton(
                  icon: const Icon(LucideIcons.squarePen, size: 20),
                  onPressed: _renaming ? null : _rename,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Session ID 只在这里出现（§8）：点击复制。
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: session.sessionId));
                showAppToast(context, l10n.copied);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        l10n.sessionId,
                        style: TextStyle(fontSize: 14, color: scheme.mutedForeground),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        session.sessionId,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(LucideIcons.copy, size: 15, color: scheme.mutedForeground),
                  ],
                ),
              ),
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
                        style: TextStyle(fontSize: 14, color: scheme.mutedForeground),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 14,
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

  Future<void> _rename() async {
    final l10n = AppLocalizations.of(context)!;
    final session = ref
        .read(sessionsProvider)
        .value!
        .where((s) => s.sessionId == widget.sessionId)
        .first;
    final controller = TextEditingController(text: session.name);
    final name = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(l10n.sessionRenameTitle),
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
      ),
    );
    if (name == null) return;
    setState(() => _renaming = true);
    try {
      await ref.read(sessionRepositoryProvider).rename(sessionId: widget.sessionId, name: name);
      ref.invalidate(sessionsProvider);
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  String _fmt(DateTime t) {
    final local = t.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
