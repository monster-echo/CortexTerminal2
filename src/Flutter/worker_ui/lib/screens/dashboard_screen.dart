import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/section_header.dart';
import '../widgets/states.dart';
import '../widgets/status_card.dart';
import 'auth_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.service});

  final CortermService service;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Status> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.status();
  }

  void _reload() {
    setState(() => _future = widget.service.status());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: t(context, 'nav.dashboard'),
            trailing: ShadIconButton.ghost(
              onPressed: _reload,
              icon: Icon(LucideIcons.refreshCw, size: 18),
            ),
          ),
          FutureBuilder<Status>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(padding: EdgeInsets.all(40), child: SmallSpinner()),
                );
              }
              if (snapshot.hasError) {
                return ErrorBanner(message: snapshot.error.toString(), onRetry: _reload);
              }
              final s = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _authBanner(context, s),
                  const SizedBox(height: 16),
                  StatusCard(
                    title: t(context, 'dashboard.status'),
                    items: [
                      (t(context, 'dashboard.version'), s.version),
                      (t(context, 'dashboard.uptime'), s.uptime),
                      (t(context, 'dashboard.gateway'), s.gateway),
                      (t(context, 'dashboard.workerId'), s.workerId),
                    ],
                  ),
                  if (s.authenticated) ...[
                    const SizedBox(height: 16),
                    StatusCard(
                      title: t(context, 'dashboard.auth'),
                      items: [
                        (t(context, 'dashboard.user'), s.user ?? '—'),
                        (t(context, 'dashboard.authExpiry'), s.authExpiry ?? '—'),
                      ],
                    ),
                  ],
                  if (s.gatewayVersion != null) ...[
                    const SizedBox(height: 16),
                    StatusCard(
                      title: t(context, 'dashboard.gatewayInfo'),
                      items: [
                        (t(context, 'dashboard.gatewayVersion'), s.gatewayVersion ?? '—'),
                        (t(context, 'dashboard.latestWorker'), s.latestWorkerVersion ?? '—'),
                        (
                          t(context, 'dashboard.updateAvailable'),
                          s.updateAvailable
                              ? t(context, 'dashboard.updateAvailableYes')
                              : t(context, 'dashboard.updateAvailableNo'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _workersSection(context, s),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _authBanner(BuildContext context, Status s) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    final color = s.authenticated ? scheme.tertiary : scheme.destructive;
    final label = s.authenticated ? t(context, 'dashboard.authenticated') : t(context, 'dashboard.notAuthenticated');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            s.authenticated ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
          // 未认证：直达登录页（进入即显示登录二维码，扫码即完成）
          if (!s.authenticated)
            ShadButton.outline(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: WorkerAppBar(title: t(context, 'nav.auth')),
                    body: AuthScreen(service: widget.service),
                  ),
                ),
              ),
              child: Text(t(context, 'auth.login')),
            ),
        ],
      ),
    );
  }

  Widget _workersSection(BuildContext context, Status s) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: t(context, 'dashboard.workers')),
        if (s.workers.isEmpty)
          Text(
            t(context, 'dashboard.workersEmpty'),
            style: TextStyle(color: scheme.mutedForeground, fontSize: 14),
          )
        else
          AppGroupCard(
            children: [
              for (var i = 0; i < s.workers.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Builder(
                  builder: (context) {
                    final w = s.workers[i];
                    return AppRow(
                      icon: LucideIcons.cpu,
                      label: w.displayName,
                      value:
                          '${w.operatingSystem ?? ''}  v${w.version ?? '—'}'
                          '${w.isOnline ? '' : '  (${t(context, 'dashboard.offline')})'}',
                      trailing: w.isOnline
                          ? Text(t(context, 'dashboard.online'),
                              style: TextStyle(color: scheme.tertiary, fontSize: 13))
                          : null,
                      leadingWidget: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: w.isOnline ? scheme.tertiary : scheme.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
      ],
    );
  }
}
