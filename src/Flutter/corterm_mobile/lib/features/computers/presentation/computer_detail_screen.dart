import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/models/workspace.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/swipe_delete.dart';
import '../../../shared/utils/relative_time.dart';
import '../../workers/data/workspace_repository.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../workspaces/data/workspace_providers.dart';

/// 电脑详情（design/01 §5/§3）：名称与在线状态 + 该电脑下的工作区列表。
/// 不展示 CPU/RAM/IP/版本统计（§2 禁止）。
class ComputerDetailScreen extends ConsumerWidget {
  const ComputerDetailScreen({required this.workerId, super.key});

  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final workers = ref.watch(workersProvider);
    final workspaces = ref.watch(workspacesProvider);

    return AdaptivePageScaffold(
      backgroundColor: colorsOf(context).background,
      appBar: CortermAppBar(
        title: l10n.computersTitle,
        actions: [
          IconButton(
            tooltip: l10n.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(workersProvider);
              ref.invalidate(workspacesProvider);
            },
          ),
        ],
      ),
      body: workers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '$error',
              style: TextStyle(color: colorsOf(context).danger),
            ),
          ),
        ),
        data: (list) {
          final worker = list.where((w) => w.workerId == workerId).firstOrNull;
          if (worker == null) {
            return EmptyState(
              icon: Icons.computer,
              message: l10n.computerUnavailable,
            );
          }
          return ListView(
            children: [
              ListRow(
                title: worker.displayName,
                subtitle: worker.isOnline
                    ? l10n.workerOnline
                    : l10n.workerOffline,
                leading: _StatusDot(online: worker.isOnline),
              ),
              if (worker.lastSeenAtUtc != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${Localizations.localeOf(context).languageCode == 'zh' ? '最近在线' : 'Last seen'} · ${relativeTime(worker.lastSeenAtUtc!, languageCode: Localizations.localeOf(context).languageCode)}',
                  ),
                ),
              if (!worker.isOnline)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'zh'
                        ? '请在这台电脑上启动云枢终端并保持联网，然后刷新。'
                        : 'Start Corterm on this computer, keep it online, then refresh.',
                  ),
                ),
              SectionHeader(l10n.workspacesSectionTitle),
              workspaces.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '$error',
                    style: TextStyle(color: colorsOf(context).danger),
                  ),
                ),
                data: (all) {
                  final items = all
                      .where((w) => w.workerId == workerId)
                      .toList();
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: EmptyState(
                        icon: Icons.folder_open,
                        message: l10n.workspaceEmpty,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final w in items) _WorkspaceRow(workspace: w),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: PrimaryButton(
                  label: l10n.workspaceCreateTitle,
                  onPressed: () =>
                      context.push('/workspaces/new?workerId=$workerId'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: online ? c.success : c.textSecondary,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _WorkspaceRow extends ConsumerWidget {
  const _WorkspaceRow({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return SwipeDelete(
      key: ValueKey(workspace.workspaceId),
      title: zh ? '删除工作区' : 'Delete workspace',
      message: zh
          ? '删除「${workspace.displayName}」及其会话记录？电脑上的文件会保留。'
          : 'Delete "${workspace.displayName}" and its session records? Computer files will be kept.',
      onDelete: () async {
        await ref
            .read(workspaceRepositoryProvider)
            .delete(workspace.workspaceId);
        ref.invalidate(workspacesProvider);
        ref.invalidate(sessionsProvider);
      },
      child: ListRow(
        title: workspace.displayName,
        subtitle: workspace.rootPath,
        onTap: () => context.push('/workspaces/${workspace.workspaceId}'),
        trailing: Icon(
          Icons.chevron_right,
          color: colorsOf(context).textSecondary,
        ),
      ),
    );
  }
}
