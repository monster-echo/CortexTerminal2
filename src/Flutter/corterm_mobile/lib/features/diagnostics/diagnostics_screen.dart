import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/platform/sysinfo.dart';
import '../../shared/widgets/app_bar.dart';
import '../../shared/widgets/list_group.dart';

import '../../core/config/app_config.dart';
import '../../features/sessions/data/sessions_providers.dart';
import '../../features/session/widgets/session_status.dart';
import '../../features/session/session_controller.dart';
import '../../features/session/session_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/connection_status_dot.dart';

/// 诊断页（阶段4）：连接自检 + 打开会话的实时连接状态。
/// 按「不在 UI 体现 gateway」的要求，不展示网关地址，仅展示可达性与版本。
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _ProbeResult {
  final int? latencyMs;
  final Object? error;
  _ProbeResult(this.latencyMs, this.error);
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  late Future<_ProbeResult> _probe = _runProbe();

  Future<_ProbeResult> _runProbe() async {
    final base = ref.read(appConfigProvider);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));
    final watch = Stopwatch()..start();
    try {
      await dio.head<dynamic>(base);
      watch.stop();
      return _ProbeResult(watch.elapsedMilliseconds, null);
    } catch (e) {
      watch.stop();
      return _ProbeResult(null, e);
    } finally {
      dio.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final ws = ref.watch(sessionControllerProvider);
    final sessions = ref.watch(sessionsProvider);
    final gatewayInfo = ref.watch(gatewayInfoProvider);

    final opened = ws.openedSessionIds
        .map((id) => (id, ws.entryOf(id)))
        .where((e) => e.$2 != null)
        .toList();

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: l10n.diagnostics,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          AppGroupHeader(l10n.connection),
          AppGroupCard(children: [
            FutureBuilder<_ProbeResult>(
              future: _probe,
              builder: (context, snap) {
                final r = snap.data;
                return AppRow(
                  icon: LucideIcons.gauge,
                  label: l10n.gatewayReachable,
                  value: r == null
                      ? l10n.diagnosticTesting
                      : (r.error == null ? l10n.ms(r.latencyMs!) : l10n.diagnosticFail),
                  valueColor: r?.error != null ? scheme.destructive : null,
                );
              },
            ),
            AppRow(
              icon: LucideIcons.cloud,
              label: l10n.gatewayVersion,
              value: gatewayInfo.valueOrNull?.version ?? '—',
            ),
            AppRow(
              icon: LucideIcons.smartphone,
              label: l10n.platform,
              value: platformLabel(),
            ),
          ]),
          ShadButton.ghost(
            onPressed: () => setState(() => _probe = _runProbe()),
            leading: const Icon(LucideIcons.refreshCw, size: 18),
            child: Text(l10n.retry),
          ),

          AppGroupHeader(l10n.openSessions),
          if (opened.isEmpty)
            AppGroupCard(children: [
              AppRow(icon: LucideIcons.terminal, label: l10n.noActiveSessions),
            ])
          else
            AppGroupCard(children: [
              for (final (id, entry) in opened)
                AppRow(
                  leadingWidget: ConnectionStatusDot(
                    color: connDotStyle(ShadTheme.of(context).colorScheme, entry!.connState).$1,
                    pulse: connDotStyle(ShadTheme.of(context).colorScheme, entry.connState).$2,
                  ),
                  label:
                      sessions.value?.where((s) => s.sessionId == id).firstOrNull?.displayName ??
                          id.substring(0, 8),
                  value: switch (entry.connState) {
                    TerminalConnState.live =>
                      '${l10n.connLive}${entry.rttMs != null ? ' · ${l10n.ms(entry.rttMs!)}' : ''}',
                    TerminalConnState.connecting => l10n.connConnecting,
                    TerminalConnState.replaying => l10n.connReplaying,
                    TerminalConnState.reconnecting => l10n.connReconnecting,
                    TerminalConnState.idle => l10n.connIdle,
                    TerminalConnState.exited => l10n.connExited,
                    TerminalConnState.error =>
                      l10n.connError + (entry.errorMessage == null ? '' : ' · ${entry.errorMessage}'),
                  },
                ),
            ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
