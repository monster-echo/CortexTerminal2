import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/corterm_theme.dart';
import '../../core/models/session.dart';
import '../../core/models/worker.dart';
import '../../core/models/workspace.dart';
import '../../shared/widgets/corterm_ui.dart';
import '../sessions/data/sessions_providers.dart';
import '../workspaces/data/workspace_providers.dart';

/// 首页（design/01 §1-§3）：☰ [ 工作区 | 电脑 ] +。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0; // 0 = 工作区, 1 = 电脑
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: const CortermSidebar(),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.menu, color: c.textPrimary),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Expanded(
                    child: Center(
                      child: _SegmentedTabs(
                        labels: const ['工作区', '电脑'],
                        index: _tab,
                        onChanged: (i) => setState(() => _tab = i),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add, color: c.textPrimary),
                    onPressed: () => context.push(_tab == 0
                        ? '/workspaces/new'
                        : '/computers/new'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tab == 0 ? const _WorkspaceTab() : const _ComputerTab(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                decoration: BoxDecoration(
                  color: i == index ? c.surfaceSelected : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(9)),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        i == index ? FontWeight.w600 : FontWeight.w400,
                    color: i == index ? c.textPrimary : c.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 工作区 Tab（design/01 §2）：名称 / 所属电脑 / 会话数或最近活动。
class _WorkspaceTab extends ConsumerWidget {
  const _WorkspaceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colorsOf(context);
    final workspaces = ref.watch(workspacesProvider);
    final workers = ref.watch(workersProvider);

    return workspaces.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.danger, fontSize: 14)),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
              icon: Icons.folder_outlined, message: '还没有工作区，点右上角 + 新建');
        }
        final workerMap = <String, WorkerSummary>{
          for (final w in workers.value ?? const <WorkerSummary>[]) w.workerId: w,
        };
        final ungrouped = ref.watch(ungroupedSessionsProvider);
        return RefreshIndicator(
          onRefresh: () async => ref.refresh(workspacesProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              for (final w in list)
                _WorkspaceRow(workspace: w, worker: workerMap[w.workerId]),
              if (ungrouped.isNotEmpty)
                ListRow(
                  title: '未分组会话',
                  subtitle: '${ungrouped.length} 个会话未关联工作区',
                  leading: const Icon(Icons.inbox_outlined,
                      color: Color(0xFF6F6F6F)),
                  trailing: const Icon(Icons.chevron_right,
                      color: Color(0xFF6F6F6F)),
                  onTap: () => context.push('/sessions/ungrouped'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceRow extends ConsumerWidget {
  const _WorkspaceRow({required this.workspace, required this.worker});

  final Workspace workspace;
  final WorkerSummary? worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colorsOf(context);
    final sessions = ref.watch(workspaceSessionsProvider(workspace.workspaceId));
    final running = sessions.where((s) => s.status.isRunning).length;
    final subtitle = sessions.isEmpty
        ? (worker?.displayName ?? '')
        : '${worker?.displayName ?? ''} · $running 个会话运行中';

    return ListRow(
      title: workspace.displayName,
      subtitle: subtitle,
      leading: Icon(Icons.folder_outlined, color: c.textSecondary),
      trailing: Icon(Icons.chevron_right, color: c.textSecondary),
      onTap: () => context.push('/workspaces/${workspace.workspaceId}'),
    );
  }
}

/// 电脑 Tab（design/01 §3）：已配对 Worker 列表。
class _ComputerTab extends ConsumerWidget {
  const _ComputerTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colorsOf(context);
    final workers = ref.watch(workersProvider);
    final workspaces = ref.watch(workspacesProvider);

    return workers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.danger, fontSize: 14)),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(icon: Icons.computer_outlined, message: '还没有配对电脑，点右上角 + 添加');
        }
        final ws = workspaces.value ?? const <Workspace>[];
        return RefreshIndicator(
          onRefresh: () async => ref.refresh(workersProvider.future),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final w = list[i];
              final count = ws.where((x) => x.workerId == w.workerId).length;
              return ListRow(
                title: w.displayName,
                subtitle:
                    '${w.isOnline ? '在线' : '离线'} · $count 个工作区',
                leading: Icon(Icons.computer_outlined, color: c.textSecondary),
                trailing: Icon(Icons.chevron_right, color: c.textSecondary),
                onTap: () => context.push('/computers/${w.workerId}'),
              );
            },
          ),
        );
      },
    );
  }
}

/// 侧边栏（design/01 §4）：顶部 Corterm + 🔍；工作区最多 5 个、首个默认展开；
/// 底部 + 新建（新建 Session）与用户头像。
class CortermSidebar extends ConsumerStatefulWidget {
  const CortermSidebar({super.key});

  @override
  ConsumerState<CortermSidebar> createState() => _CortermSidebarState();
}

class _CortermSidebarState extends ConsumerState<CortermSidebar> {
  static const _maxVisible = 5;
  String? _expandedId;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final workspaces = ref.watch(workspacesProvider);

    return Drawer(
      backgroundColor: c.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Corterm',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: c.textPrimary)),
                  ),
                  IconButton(
                    icon: Icon(Icons.search, color: c.textSecondary),
                    onPressed: () => context.push('/search'),
                  ),
                ],
              ),
            ),
            Divider(color: c.divider),
            Expanded(
              child: workspaces.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                    child: Text('$e',
                        style: TextStyle(color: c.danger, fontSize: 14))),
                data: (list) {
                  // 首个默认展开（§5），无工作区时无需展开态。
                  final expanded =
                      _expandedId ?? (list.isNotEmpty ? list.first.workspaceId : null);
                  final visible = _showAll ? list : list.take(_maxVisible).toList();
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final ws in visible)
                        _SidebarWorkspace(
                          workspace: ws,
                          expanded: ws.workspaceId == expanded,
                          onToggle: () => setState(() =>
                              _expandedId = ws.workspaceId == expanded
                                  ? null
                                  : ws.workspaceId),
                        ),
                      if (!_showAll && list.length > _maxVisible)
                        TextButton(
                          onPressed: () => setState(() => _showAll = true),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('更多工作区',
                                style: TextStyle(
                                    fontSize: 14, color: c.textSecondary)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Divider(color: c.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => context.push('/sessions/new'),
                      icon: Icon(Icons.add, color: c.textPrimary),
                      label: Text('新建',
                          style:
                              TextStyle(fontSize: 15, color: c.textPrimary)),
                      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.account_circle_outlined,
                        color: c.textSecondary),
                    onPressed: () => context.push('/me'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarWorkspace extends ConsumerWidget {
  const _SidebarWorkspace({
    required this.workspace,
    required this.expanded,
    required this.onToggle,
  });

  final Workspace workspace;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colorsOf(context);
    final sessions = ref.watch(workspaceSessionsProvider(workspace.workspaceId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 18, color: c.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(workspace.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 15, color: c.textPrimary)),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: c.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: sessions.isEmpty
                ? Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text('无会话',
                        style:
                            TextStyle(fontSize: 13, color: c.textSecondary)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in sessions)
                        InkWell(
                          onTap: () =>
                              context.push('/sessions/${s.sessionId}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 7),
                            child: Row(
                              children: [
                                Icon(
                                  s.status.isRunning
                                      ? Icons.circle
                                      : Icons.circle_outlined,
                                  size: 8,
                                  color: s.status.isRunning
                                      ? c.success
                                      : c.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_sessionTitle(s),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: c.textSecondary)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      InkWell(
                        onTap: () => context.push(
                            '/sessions/new?workspaceId=${workspace.workspaceId}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 7),
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 16, color: c.textSecondary),
                              const SizedBox(width: 8),
                              Text('新建会话',
                                  style: TextStyle(
                                      fontSize: 14, color: c.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

String _sessionTitle(SessionSummary s) =>
    s.name.isNotEmpty ? s.name : '终端 ${s.sessionId.substring(0, 8)}';
