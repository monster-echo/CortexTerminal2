import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/workspace.dart';
import '../../../shared/widgets/app_bar.dart';
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
    final workers = ref.watch(workersProvider);
    final workspaces = ref.watch(workspacesProvider);

    return Scaffold(
      backgroundColor: colorsOf(context).background,
      appBar: CortermAppBar(
        title: '电脑',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(workersProvider),
          ),
        ],
      ),
      body: workers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$error', style: TextStyle(color: colorsOf(context).danger)),
          ),
        ),
        data: (list) {
          final worker =
              list.where((w) => w.workerId == workerId).first;
          return ListView(
            children: [
              ListRow(
                title: worker.displayName,
                subtitle: worker.isOnline ? '在线' : '离线',
                leading: _StatusDot(online: worker.isOnline),
              ),
              const SectionHeader('工作区'),
              workspaces.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('$error',
                      style: TextStyle(color: colorsOf(context).danger)),
                ),
                data: (all) {
                  final items = all
                      .where((w) => w.workerId == workerId)
                      .toList();
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: EmptyState(
                        icon: Icons.folder_open,
                        message: '还没有工作区',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final w in items)
                        _WorkspaceRow(workspace: w),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: PrimaryButton(
                  label: '新建工作区',
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

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      title: workspace.displayName,
      subtitle: workspace.rootPath,
      onTap: () => context.push('/workspaces/${workspace.workspaceId}'),
      trailing: Icon(Icons.chevron_right,
          color: colorsOf(context).textSecondary),
    );
  }
}
