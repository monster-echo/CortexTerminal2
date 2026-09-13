import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/widgets/app_bar.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/connection_status_dot.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/list_group.dart';
import '../sessions/data/sessions_providers.dart';
import '../workspace/widgets/new_session_sheet.dart';
import '../workspace/widgets/session_list_item.dart';
import '../workspace/widgets/session_status.dart';
import '../workspace/workspace_controller.dart';

/// Home（§47/§48）：概览页 —— Running Sessions / Recent Sessions / Workers / New Session。
/// 不做 Dashboard；点击 session 直接进入 Workspace，不进详情页。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final overview = ref.watch(homeOverviewProvider);
    final workers = ref.watch(workersProvider);

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        title: l10n.homeTitle,
        actions: [
          ShadIconButton.ghost(
            foregroundColor: scheme.foreground,
            icon: const Icon(LucideIcons.slidersHorizontal, size: 22),
            onPressed: () => context.go('/sessions'),
          ),
          ShadIconButton.ghost(
            foregroundColor: scheme.foreground,
            icon: Icon(LucideIcons.settings, size: 22),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sessionsProvider);
          ref.invalidate(workersProvider);
          await Future.wait([
            ref.read(sessionsProvider.future),
            ref.read(workersProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            ShadButton(
              leading: const Icon(LucideIcons.plus, size: 18),
              onPressed: () => showNewSessionSheet(
                context,
                onCreated: (sessionId) {
                  ref.read(workspaceControllerProvider.notifier).open(sessionId);
                  context.go('/workspace');
                },
              ),
              child: Text(l10n.newSession),
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.runningSessions),
            if (overview.running.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.noActiveSessions,
                  style: TextStyle(color: scheme.mutedForeground),
                ),
              )
            else ...[
              for (final s in overview.running)
                SessionListItem(
                  session: s,
                  onTap: () {
                    ref.read(workspaceControllerProvider.notifier).open(s.sessionId);
                    context.go('/workspace');
                  },
                ),
            ],
            const SizedBox(height: 8),
            _SectionTitle(l10n.recentSessions),
            if (overview.recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.noSessions,
                  style: TextStyle(color: scheme.mutedForeground),
                ),
              )
            else ...[
              for (final s in overview.recent)
                SessionListItem(
                  session: s,
                  onTap: () {
                    ref.read(workspaceControllerProvider.notifier).open(s.sessionId);
                    context.go('/workspace');
                  },
                ),
            ],
            const SizedBox(height: 8),
            _SectionTitle(l10n.workers),
            workers.when(
              loading: () => const SmallSpinner(),
              error: (e, _) => ErrorState(message: l10n.noWorkers, onRetry: () {
                ref.invalidate(workersProvider);
              }),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.noWorkers,
                        style: TextStyle(color: scheme.mutedForeground),
                      ),
                    )
                  : Column(
                      children: [
                        for (final w in list)
                          AppRow(
                            contentPadding: EdgeInsets.zero,
                            leadingWidget: ConnectionStatusDot(color: workerDotColor(w)),
                            label: w.displayName,
                            value: w.isOnline ? l10n.workerOnline : l10n.workerOffline,
                            trailing: Text(
                              '${w.sessionCount}',
                              style: TextStyle(fontSize: 12, color: scheme.mutedForeground),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          color: ShadTheme.of(context).colorScheme.mutedForeground,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
