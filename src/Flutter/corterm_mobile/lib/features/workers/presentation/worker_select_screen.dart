import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/models/worker.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../sessions/data/sessions_providers.dart';

/// 电脑选择页（design/02：选择类操作用独立页面，与文件夹选择一致）。
/// 点选一台电脑后 pop 返回 [WorkerSummary]。
class WorkerSelectScreen extends ConsumerWidget {
  const WorkerSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final workersAsync = ref.watch(workersProvider);

    return AdaptivePageScaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.selectComputerTitle),
        actions: [
          IconButton(
            tooltip: l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(workersProvider),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch (workersAsync) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.danger),
              ),
            ),
          ),
          AsyncValue(:final value) =>
            (value ?? const []).isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EmptyState(
                          icon: Icons.computer_outlined,
                          message: l10n.noWorkers,
                        ),
                        TextButton.icon(
                          onPressed: () => context.push('/computers/new'),
                          icon: const Icon(Icons.add),
                          label: Text(l10n.connectComputer),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      for (final w
                          in (value ?? const <WorkerSummary>[]).toList()..sort((
                            a,
                            b,
                          ) {
                            if (a.isOnline != b.isOnline) {
                              return a.isOnline ? -1 : 1;
                            }
                            final activity = (b.lastSeenAtUtc ?? DateTime(1970))
                                .compareTo(a.lastSeenAtUtc ?? DateTime(1970));
                            return activity != 0
                                ? activity
                                : a.displayName.compareTo(b.displayName);
                          }))
                        ListRow(
                          title: w.displayName,
                          subtitle:
                              '${w.isOnline ? l10n.workerOnline : l10n.workerOffline} · ${w.hostname ?? ''}${w.isOnline ? '' : (Localizations.localeOf(context).languageCode == 'zh' ? ' · 请先启动电脑端应用' : ' · Start Corterm on this computer')}',
                          leading: Icon(
                            Icons.computer_outlined,
                            color: w.isOnline
                                ? colors.textSecondary
                                : colors.textSecondary.withValues(alpha: 0.4),
                          ),
                          trailing: w.isOnline
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  tooltip: l10n.computersTitle,
                                  icon: const Icon(Icons.info_outline),
                                  onPressed: () =>
                                      context.push('/computers/${w.workerId}'),
                                ),
                          onTap: w.isOnline
                              ? () => Navigator.pop(context, w)
                              : null, // 离线不可选
                        ),
                    ],
                  ),
        },
      ),
    );
  }
}
