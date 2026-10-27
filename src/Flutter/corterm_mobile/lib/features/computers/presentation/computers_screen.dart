import '../../../shared/layout/adaptive_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../sessions/data/sessions_providers.dart';

/// Sidebar destination for browsing computers. Selection stays a separate page.
class ComputersScreen extends ConsumerWidget {
  const ComputersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = colorsOf(context);
    final workers = ref.watch(workersProvider);
    return AdaptivePageScaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(l10n.computersTitle),
        actions: [
          IconButton(
            tooltip: l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(workersProvider),
          ),
        ],
      ),
      body: workers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(workersProvider),
            child: Text('${l10n.retry}: $error'),
          ),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.refresh(workersProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: EmptyState(
                    icon: Icons.computer_outlined,
                    message: l10n.noWorkers,
                  ),
                ),
              for (final worker
                  in (list.toList()..sort((a, b) {
                    if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
                    return a.displayName.compareTo(b.displayName);
                  })))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    child: ListRow(
                      title: worker.displayName,
                      subtitle:
                          worker.hostname == null ||
                              worker.hostname!.isEmpty ||
                              worker.hostname == worker.displayName
                          ? (worker.isOnline
                                ? l10n.workerOnline
                                : l10n.workerOffline)
                          : '${worker.isOnline ? l10n.workerOnline : l10n.workerOffline} · ${worker.hostname}',
                      leading: Icon(
                        Icons.computer_outlined,
                        color: worker.isOnline
                            ? colors.success
                            : colors.textSecondary,
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: colors.textSecondary,
                      ),
                      onTap: () =>
                          context.push('/computers/${worker.workerId}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: PrimaryButton(
          label: l10n.connectComputer,
          onPressed: () => context.push('/activate'),
        ),
      ),
    );
  }
}
