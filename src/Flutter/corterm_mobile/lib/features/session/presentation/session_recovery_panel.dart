import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../session_controller.dart';
import '../../../shared/widgets/states.dart';
import '../session_diagnostics.dart';

/// Read-only diagnosis and non-destructive reattachment. No shell restart here.
class SessionRecoveryPanel extends ConsumerStatefulWidget {
  const SessionRecoveryPanel({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<SessionRecoveryPanel> createState() =>
      _SessionRecoveryPanelState();
}

class _SessionRecoveryPanelState extends ConsumerState<SessionRecoveryPanel> {
  bool _busy = false;
  bool _reconnecting = false;
  bool _failed = false;
  bool _guide = false;
  SessionDiagnostic? _report;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await ref
          .read(sessionDiagnosticsProvider)
          .check(widget.sessionId);
      if (mounted) setState(() => _report = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _summary(AppLocalizations t) {
    final report = _report;
    if (_busy) return t.terminalChecking;
    if (_failed || report == null) return t.terminalDiagnosticUnavailable;
    if (report.hasOutput) return t.terminalDiagnosticReady;
    if (report.state == 'worker-offline') return t.terminalWorkerOffline;
    if (report.state == 'unknown-session') return t.terminalSessionGone;
    if (report.state == 'diagnostics-unavailable' ||
        report.state == 'diagnostic-timeout' ||
        report.state == 'diagnostic-busy') {
      return t.terminalDiagnosticUnavailable;
    }
    return switch (report.directoryAccess) {
      'permission-denied' => t.terminalDirectoryDenied,
      'timed-out' => t.terminalDirectoryTimeout,
      'unavailable' => t.terminalDirectoryUnavailable,
      _ => t.terminalStartupUnknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isMac = _report?.platform == 'macos';
    final macMayNeedAccess =
        isMac &&
        !(_report?.hasOutput ?? true) &&
        ['permission-denied', 'timed-out'].contains(_report?.directoryAccess);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t.terminalRunDiagnostics,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Semantics(liveRegion: true, child: Text(_summary(t))),
        if (_report?.directory case final String directory) ...[
          const SizedBox(height: 12),
          SelectableText(directory),
        ],
        const SizedBox(height: 16),
        Text(t.terminalReconnectHelp),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _check,
              child: Text(t.terminalRecheck),
            ),
            OutlinedButton(
              onPressed: _reconnecting
                  ? null
                  : () async {
                      setState(() => _reconnecting = true);
                      try {
                        await ref
                            .read(sessionControllerProvider.notifier)
                            .reconnect(widget.sessionId);
                        if (context.mounted) Navigator.of(context).pop();
                      } catch (error) {
                        if (context.mounted) {
                          showAppToast(context, '$error', destructive: true);
                        }
                      } finally {
                        if (mounted) setState(() => _reconnecting = false);
                      }
                    },
              child: Text(t.reconnectAction),
            ),
          ],
        ),
        if (isMac || _report?.platform == 'unknown' || _failed) ...[
          TextButton(
            onPressed: () => setState(() => _guide = !_guide),
            child: Text(t.terminalPermissionGuide),
          ),
          if (_guide || macMayNeedAccess) Text(t.terminalRemoteMacSteps),
        ],
      ],
    );
  }
}
