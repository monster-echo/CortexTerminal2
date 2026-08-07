import 'package:flutter/material.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_header.dart';
import '../widgets/status_card.dart';

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
            trailing: IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ),
          FutureBuilder<Status>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
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
    final scheme = Theme.of(context).colorScheme;
    final color = s.authenticated ? scheme.tertiary : scheme.error;
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
            s.authenticated ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _workersSection(BuildContext context, Status s) {
    final t = AppStrings.t;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: t(context, 'dashboard.workers')),
        if (s.workers.isEmpty)
          Text(
            t(context, 'dashboard.workersEmpty'),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          )
        else
          ...s.workers.map(
            (w) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 5,
                  backgroundColor: w.isOnline ? scheme.tertiary : scheme.outlineVariant,
                ),
                title: Text(w.displayName, style: const TextStyle(fontSize: 15)),
                subtitle: Text(
                  '${w.operatingSystem ?? ''}  v${w.version ?? '—'}'
                  '${w.isOnline ? '' : '  (${t(context, 'dashboard.offline')})'}',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: w.isOnline
                    ? Text(t(context, 'dashboard.online'),
                        style: TextStyle(color: scheme.tertiary, fontSize: 13))
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
