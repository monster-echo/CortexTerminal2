import '../../shared/layout/adaptive_page_scaffold.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/states.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/theme/corterm_theme.dart';
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
  DateTime? _checkedAt;
  _ProbeResult? _latest;
  bool _probing = false;

  Future<_ProbeResult> _runProbe() async {
    _probing = true;
    final base = ref.read(appConfigProvider);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final watch = Stopwatch()..start();
    try {
      await dio.head<dynamic>(base);
      watch.stop();
      return _latest = _ProbeResult(watch.elapsedMilliseconds, null);
    } catch (e) {
      watch.stop();
      return _latest = _ProbeResult(null, e);
    } finally {
      if (mounted) {
        setState(() {
          _checkedAt = DateTime.now();
          _probing = false;
        });
      }
      dio.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = colorsOf(context);
    final ws = ref.watch(sessionControllerProvider);
    final sessions = ref.watch(sessionsProvider);
    final gatewayInfo = ref.watch(gatewayInfoProvider);

    final opened = ws.openedSessionIds
        .map((id) => (id, ws.entryOf(id)))
        .where((e) => e.$2 != null)
        .toList();

    return AdaptivePageScaffold(
      backgroundColor: c.background,
      appBar: CortermAppBar(
        leading: ShadIconButton.ghost(
          foregroundColor: c.textPrimary,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: l10n.diagnostics,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          AppGroupHeader(l10n.connection),
          AppGroupCard(
            children: [
              FutureBuilder<_ProbeResult>(
                future: _probe,
                builder: (context, snap) {
                  final r = snap.data;
                  return AppRow(
                    icon: LucideIcons.gauge,
                    label: l10n.gatewayReachable,
                    value: r == null
                        ? l10n.diagnosticTesting
                        : (r.error == null
                              ? l10n.ms(r.latencyMs!)
                              : l10n.diagnosticFail),
                    valueColor: r?.error != null ? c.danger : null,
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
            ],
          ),

          FutureBuilder<_ProbeResult>(
            future: _probe,
            builder: (context, snapshot) => Column(
              children: [
                if (snapshot.connectionState == ConnectionState.done &&
                    _checkedAt != null)
                  Text(
                    '${Localizations.localeOf(context).languageCode == 'zh' ? '检查时间' : 'Checked'}: ${_checkedAt!.toLocal()}',
                  ),
                if (snapshot.data?.error != null)
                  ExpansionTile(
                    title: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '连接失败详情'
                          : 'Connection error details',
                    ),
                    children: [SelectableText('${snapshot.data!.error}')],
                  ),
              ],
            ),
          ),
          ShadButton.ghost(
            enabled: !_probing,
            onPressed: () => setState(() {
              ref.invalidate(gatewayInfoProvider);
              _probe = _runProbe();
            }),
            leading: const Icon(LucideIcons.refreshCw, size: 18),
            child: Text(l10n.retry),
          ),

          AppGroupHeader(l10n.openSessions),
          if (opened.isEmpty)
            AppGroupCard(
              children: [
                AppRow(
                  icon: LucideIcons.terminal,
                  label: l10n.noActiveSessions,
                ),
              ],
            )
          else
            AppGroupCard(
              children: [
                for (final (id, entry) in opened)
                  AppRow(
                    leadingWidget: ConnectionStatusDot(
                      color: connDotStyle(
                        colorsOf(context),
                        entry!.connState,
                      ).$1,
                      pulse: connDotStyle(
                        colorsOf(context),
                        entry.connState,
                      ).$2,
                    ),
                    label:
                        sessions.value
                            ?.where((s) => s.sessionId == id)
                            .firstOrNull
                            ?.displayName ??
                        id,
                    value: switch (entry.connState) {
                      TerminalConnState.live =>
                        '${l10n.connLive}${entry.rttMs != null ? ' · ${l10n.ms(entry.rttMs!)}' : ''}',
                      TerminalConnState.connecting => l10n.connConnecting,
                      TerminalConnState.replaying => l10n.connReplaying,
                      TerminalConnState.reconnecting => l10n.connReconnecting,
                      TerminalConnState.workerOffline => l10n.workerOffline,
                      TerminalConnState.idle => l10n.connIdle,
                      TerminalConnState.exited => l10n.connExited,
                      TerminalConnState.error =>
                        l10n.connError +
                            (entry.errorMessage == null
                                ? ''
                                : ' · ${entry.errorMessage}'),
                    },
                  ),
              ],
            ),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '复制诊断摘要'
                  : 'Copy diagnostic summary',
            ),
            onPressed: () async {
              final report =
                  'Corterm diagnostics\nPlatform: ${platformLabel()}\nChecked: $_checkedAt\nGateway: ${_latest == null
                      ? 'pending'
                      : _latest!.error == null
                      ? '${_latest!.latencyMs}ms'
                      : 'unreachable'}\nVersion: ${gatewayInfo.valueOrNull?.version ?? 'unavailable'}\nConnections: ${opened.map((item) => item.$2!.connState.name).join(', ')}';
              await Clipboard.setData(ClipboardData(text: report));
              if (context.mounted) showAppToast(context, l10n.copied);
            },
          ),
          Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '摘要仅包含平台、版本、检查时间与连接状态。'
                : 'Summary includes platform, version, check time and connection states.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
