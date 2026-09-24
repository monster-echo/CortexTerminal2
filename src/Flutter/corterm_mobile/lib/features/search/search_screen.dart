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

/// 搜索（design/03）：无标题，未输入显示最近会话；输入后按 工作区/会话/电脑 分组。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final workspaces =
        ref.watch(workspacesProvider).value ?? const <Workspace>[];
    final sessions = ref.watch(sessionsProvider).value ?? const <SessionSummary>[];
    final workers = ref.watch(workersProvider).value ?? const <WorkerSummary>[];

    final q = _query.trim().toLowerCase();
    final wsHits = q.isEmpty
        ? const <Workspace>[]
        : workspaces.where((w) => _matchWorkspace(w, q)).toList();
    final sessionHits = q.isEmpty
        ? const <SessionSummary>[]
        : sessions.where((s) => _matchSession(s, q)).toList();
    final workerHits = q.isEmpty
        ? const <WorkerSummary>[]
        : workers.where((w) => _matchWorker(w, q)).toList();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: q.isEmpty
                  ? _RecentSessions(sessions: sessions.take(10).toList())
                  : ListView(
                      children: [
                        if (wsHits.isNotEmpty)
                          _Group(
                            title: '工作区',
                            children: [
                              for (final w in wsHits)
                                ListRow(
                                  title: w.displayName,
                                  subtitle: w.rootPath,
                                  leading: Icon(Icons.folder_outlined,
                                      color: c.textSecondary),
                                  onTap: () => context
                                      .push('/workspaces/${w.workspaceId}'),
                                ),
                            ],
                          ),
                        if (sessionHits.isNotEmpty)
                          _Group(
                            title: '会话',
                            children: [
                              for (final s in sessionHits)
                                ListRow(
                                  title: s.displayName,
                                  subtitle:
                                      '${_workspaceName(workspaces, s.workspaceId)} · ${s.status.isRunning ? '运行中' : '已结束'}',
                                  leading: Icon(Icons.terminal_outlined,
                                      color: c.textSecondary),
                                  onTap: () =>
                                      context.push('/sessions/${s.sessionId}'),
                                ),
                            ],
                          ),
                        if (workerHits.isNotEmpty)
                          _Group(
                            title: '电脑',
                            children: [
                              for (final w in workerHits)
                                ListRow(
                                  title: w.displayName,
                                  subtitle:
                                      '${w.isOnline ? '在线' : '离线'} · ${w.hostname ?? ''}',
                                  leading: Icon(Icons.computer_outlined,
                                      color: c.textSecondary),
                                  onTap: () =>
                                      context.push('/computers/${w.workerId}'),
                                ),
                            ],
                          ),
                        if (wsHits.isEmpty &&
                            sessionHits.isEmpty &&
                            workerHits.isEmpty)
                          const EmptyState(
                              icon: Icons.search_off, message: '无结果'),
                      ],
                    ),
            ),
            // 底部大圆角搜索 Surface（design/03 §6）。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                      decoration: InputDecoration(
                        hintText: '搜索',
                        hintStyle:
                            TextStyle(fontSize: 16, color: c.textSecondary),
                        filled: true,
                        fillColor: c.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(24)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: c.textSecondary),
                    onPressed: () => context.pop(),
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

bool _matchWorkspace(Workspace w, String q) =>
    w.name.toLowerCase().contains(q) ||
    _basename(w.rootPath).toLowerCase().contains(q) ||
    (w.rootPath ?? '').toLowerCase().contains(q);

bool _matchSession(SessionSummary s, String q) =>
    s.displayName.toLowerCase().contains(q);

bool _matchWorker(WorkerSummary w, String q) =>
    w.displayName.toLowerCase().contains(q) ||
    (w.hostname ?? '').toLowerCase().contains(q);

String _basename(String? path) {
  if (path == null || path.isEmpty) return '';
  final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = trimmed.lastIndexOf('/');
  return i >= 0 ? trimmed.substring(i + 1) : trimmed;
}

String _workspaceName(List<Workspace> list, String id) {
  for (final w in list) {
    if (w.workspaceId == id) return w.displayName;
  }
  return '';
}

class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.sessions});

  final List<SessionSummary> sessions;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    if (sessions.isEmpty) {
      return const EmptyState(icon: Icons.terminal_outlined, message: '暂无会话');
    }
    return ListView(
      children: [
        const SectionHeader('最近会话'),
        for (final s in sessions)
          ListRow(
            title: s.displayName,
            subtitle:
                '${s.workerName ?? s.workerId} · ${s.status.isRunning ? '运行中' : '已结束'}',
            leading: Icon(Icons.terminal_outlined, color: c.textSecondary),
            trailing: Icon(Icons.chevron_right, color: c.textSecondary),
            onTap: () => context.push('/sessions/${s.sessionId}'),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionHeader(title), ...children],
    );
  }
}
