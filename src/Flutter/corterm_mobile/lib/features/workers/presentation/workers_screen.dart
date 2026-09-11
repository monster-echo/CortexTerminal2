import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/list_group.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/connection_status_dot.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../sessions/data/session_repository.dart';
import '../../workspace/widgets/session_status.dart';
import '../../workspace/workspace_controller.dart';

/// Workers（阶段4）：列表 + 详情（含宿主会话）+ 升级。
class WorkersScreen extends ConsumerWidget {
  const WorkersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final workers = ref.watch(workersProvider);

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: scheme.foreground),
          onPressed: () => context.pop(),
        ),
        title: l10n.workersTitle,
      ),
      body: workers.when(
        loading: () => const SmallSpinner(),
        error: (e, _) => ErrorState(message: '$e', onRetry: () => ref.invalidate(workersProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(workersProvider);
            await ref.read(workersProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if (list.isEmpty)
                SizedBox(
                  height: 240,
                  child: EmptyState(title: l10n.noWorkers),
                ),
              for (final w in list)
                AppGroupCard(
                  children: [
                    ListTile(
                      minVerticalPadding: 14,
                      iconColor: scheme.mutedForeground,
                      textColor: scheme.foreground,
                      leading: ConnectionStatusDot(color: workerDotColor(w), size: 10),
                      title: Text(w.displayName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        w.isOnline
                            ? [w.operatingSystem, w.architecture, w.version]
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(' · ')
                            : l10n.workerOffline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: scheme.mutedForeground),
                      ),
                      trailing: Text(
                        l10n.sessionCount(w.sessionCount),
                        style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
                      ),
                      onTap: () => _showDetail(context, ref, w.workerId),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, WidgetRef ref, String workerId) async {
    final repo = ref.read(sessionRepositoryProvider);
    final l10n = AppLocalizations.of(context)!;
    WorkerDetail detail;
    try {
      detail = await repo.workerDetail(workerId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!context.mounted) return;
    await showCortermSheet(
      context: context,
      builder: (context) => _WorkerDetailSheet(detail: detail, l10n: l10n),
    );
  }
}

class _WorkerDetailSheet extends ConsumerWidget {
  const _WorkerDetailSheet({required this.detail, required this.l10n});

  final WorkerDetail detail;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ShadTheme.of(context).colorScheme;
    final w = detail.worker;
    final rows = <(String, String)>[
      (l10n.workerHostname, w.hostname ?? '—'),
      (l10n.workerOs, [w.operatingSystem, w.architecture].whereType<String>().join(' ')),
      (l10n.workerVersion, w.version ?? '—'),
      (
        l10n.lastActivity,
        w.lastSeenAtUtc != null ? _fmt(w.lastSeenAtUtc!) : '—',
      ),
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
                ConnectionStatusDot(color: workerDotColor(w), size: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    w.displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ShadButton.ghost(
                  onPressed: () => _upgrade(context, ref),
                  child: Text(l10n.upgrade),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
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
            if (detail.sessions.isNotEmpty) ...[
              const Divider(height: 20),
              SheetSectionHeader(label: l10n.sessions),
              for (final s in detail.sessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  iconColor: scheme.mutedForeground,
                  textColor: scheme.foreground,
                  leading: ConnectionStatusDot(color: sessionDotColor(s.status)),
                  title: Text(s.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.of(context).pop();
                    ref.read(workspaceControllerProvider.notifier).open(s.sessionId);
                    context.go('/workspace');
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _upgrade(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(sessionRepositoryProvider);
    try {
      final result = await repo.upgradeWorker(detail.worker.workerId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.message}${result.targetVersion == null ? '' : ' → ${result.targetVersion}'}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _fmt(DateTime t) {
    final local = t.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
