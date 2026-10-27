import '../../shared/layout/adaptive_page_scaffold.dart';
import 'adaptive_workspace_shell.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/corterm_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/storage/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/swipe_delete.dart';
import '../workers/data/workspace_repository.dart';
import '../profile/data/profile_repository.dart';
import '../profile/presentation/profile_screen.dart';
import '../../core/models/session.dart';
import '../../core/models/worker.dart';
import '../../core/models/workspace.dart';
import '../../shared/widgets/corterm_ui.dart';
import '../../shared/utils/relative_time.dart';
import '../sessions/data/sessions_providers.dart';
import '../workspaces/data/workspace_providers.dart';

/// ArkTS ShellScaffold 的 Flutter 对应页：工作区列表为根页面，侧栏负责其他一级入口。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final expanded = WorkspacePaneScope.isAvailable(context);
    return AdaptivePageScaffold(
      drawer: expanded ? null : const CortermSidebar(),
      appBar: AppBar(
        automaticallyImplyLeading: !expanded,
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.workspacesSectionTitle),
        actions: [
          IconButton(
            tooltip: l10n.workspaceCreateTitle,
            onPressed: () => context.push('/workspaces/new'),
            icon: Icon(Icons.add, size: 22, color: c.textPrimary),
          ),
        ],
      ),
      body: const _WorkspaceTab(),
    );
  }
}

/// 工作区 Tab（design/01 §2）：名称 / 所属电脑 / 会话数或最近活动。
class _WorkspaceTab extends ConsumerStatefulWidget {
  const _WorkspaceTab();

  @override
  ConsumerState<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends ConsumerState<_WorkspaceTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final workspaces = ref.watch(workspacesProvider);
    final workers = ref.watch(workersProvider);
    final sessions = ref.watch(sessionsProvider);
    final recent =
        (sessions.valueOrNull ?? const <SessionSummary>[])
            .where(
              (session) =>
                  session.status.isAlive &&
                  (workers.valueOrNull ?? const <WorkerSummary>[]).any(
                    (worker) =>
                        worker.workerId == session.workerId && worker.isOnline,
                  ),
            )
            .toList()
          ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));

    return workspaces.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.danger, fontSize: 14),
              ),
              TextButton(
                onPressed: () => ref.invalidate(workspacesProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
      data: (list) {
        final workerMap = <String, WorkerSummary>{
          for (final w in workers.asData?.value ?? const <WorkerSummary>[])
            w.workerId: w,
        };
        final ungrouped = ref.watch(ungroupedSessionsProvider);
        final query = _query.trim().toLowerCase();
        final filtered = list.where((workspace) {
          if (query.isEmpty) return true;
          final worker = workerMap[workspace.workerId];
          return '${workspace.displayName} ${workspace.rootPath ?? ''} ${worker?.displayName ?? ''}'
              .toLowerCase()
              .contains(query);
        }).toList();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(sessionsProvider);
            ref.invalidate(workersProvider);
            final refreshed = await ref.refresh(workspacesProvider.future);
            if (refreshed.isEmpty) return;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_query.isEmpty && recent.isNotEmpty) ...[
                SectionHeader(
                  Localizations.localeOf(context).languageCode == 'zh'
                      ? '继续会话'
                      : 'Continue session',
                ),
                for (final session in recent.take(3))
                  ListRow(
                    title: session.displayName,
                    subtitle:
                        '${session.workerName ?? session.workerId} · ${relativeTime(session.lastActivityAt, languageCode: Localizations.localeOf(context).languageCode)}',
                    leading: const Icon(Icons.terminal_outlined),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/sessions/${session.sessionId}'),
                  ),
                const SizedBox(height: 16),
              ],
              if (sessions.hasError || workers.hasError)
                TextButton(
                  onPressed: () {
                    ref.invalidate(sessionsProvider);
                    ref.invalidate(workersProvider);
                  },
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'zh'
                        ? '部分连接信息加载失败，点击重试'
                        : 'Some connection details are unavailable. Retry',
                  ),
                ),
              Text(
                l10n.workspaceSubtitle,
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.workspaceSearch,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .deleteButtonTooltip,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: c.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.accent),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.workspaceAll,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${filtered.length}',
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Column(
                    key: ValueKey(
                      list.isEmpty
                          ? 'no-workspaces'
                          : filtered.map((w) => w.workspaceId).join('|'),
                    ),
                    children: [
                      if (list.isEmpty)
                        EmptyState(
                          icon: Icons.folder_open_outlined,
                          message: l10n.workspaceEmpty,
                        ),
                      if (list.isEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          onPressed: workers.hasValue
                              ? () => context.push(
                                  workers.value!.isEmpty
                                      ? '/computers/new'
                                      : '/workspaces/new',
                                )
                              : null,
                          label: Text(
                            workers.valueOrNull?.isEmpty == true
                                ? l10n.connectComputer
                                : l10n.workspaceCreateTitle,
                          ),
                        ),
                      if (list.isNotEmpty && filtered.isEmpty)
                        EmptyState(
                          icon: Icons.search_off_outlined,
                          message: l10n.workspaceNoResults,
                        ),
                      for (final w in filtered)
                        _WorkspaceRow(
                          workspace: w,
                          worker: workerMap[w.workerId],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _UngroupedCard(count: ungrouped.length),
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
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(
      workspaceSessionsProvider(workspace.workspaceId),
    );
    final workerName = worker?.displayName ?? workspace.workerId;
    final online = worker?.isOnline ?? false;

    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return SwipeDelete(
      key: ValueKey('workspace-${workspace.workspaceId}'),
      title: zh ? '删除工作区' : 'Delete workspace',
      message: zh
          ? '删除「${workspace.displayName}」及所有会话记录？此操作不可撤销，电脑上的文件保留。'
          : 'Delete "${workspace.displayName}" and all its sessions? This cannot be undone. Files on the computer are kept.',
      onDelete: () async {
        await ref
            .read(workspaceRepositoryProvider)
            .delete(workspace.workspaceId);
        ref.invalidate(workspacesProvider);
        ref.invalidate(sessionsProvider);
      },
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/workspaces/${workspace.workspaceId}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 22, color: c.textPrimary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        workspace.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: c.textSecondary),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 7,
                        color: online ? c.success : c.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$workerName · ${online ? l10n.workerOnline : l10n.workerOffline}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          workspace.rootPath ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.sessionCount(sessions.length),
                        style: TextStyle(fontSize: 11, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UngroupedCard extends StatelessWidget {
  const _UngroupedCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: c.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/sessions/ungrouped'),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.terminal_rounded, size: 22, color: c.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.ungroupedSessions,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧边栏（design/01 §4）：顶部 Corterm + 🔍；工作区最多 5 个、首个默认展开；
/// 工作区列表、电脑入口与用户头像；工作区内承载 Session 创建入口。
class CortermSidebar extends ConsumerStatefulWidget {
  const CortermSidebar({super.key});

  @override
  ConsumerState<CortermSidebar> createState() => _CortermSidebarState();
}

class _CortermSidebarState extends ConsumerState<CortermSidebar> {
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _expandedId = ref
        .read(sharedPreferencesProvider)
        .getString('workspace.last_opened');
  }

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final workspaces = ref.watch(workspacesProvider);
    final workerCount = ref.watch(workersProvider).asData?.value.length ?? 0;
    final ungroupedCount = ref.watch(ungroupedSessionsProvider).length;

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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/branding/icon.png',
                      width: 30,
                      height: 30,
                      // 降采样解码（Play Vitals: downsample bitmaps）
                      cacheWidth:
                          (30 * MediaQuery.devicePixelRatioOf(context)).round(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.appName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: c.divider),
            Expanded(
              child: workspaces.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    '$e',
                    style: TextStyle(color: c.danger, fontSize: 14),
                  ),
                ),
                data: (list) {
                  final expanded = _expandedId;
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      _SidebarNavRow(
                        icon: Icons.grid_view_rounded,
                        label: l10n.workspacesSectionTitle,
                        selected: true,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      _SidebarNavRow(
                        icon: Icons.terminal_rounded,
                        label: l10n.ungroupedSessions,
                        count: ungroupedCount,
                        onTap: () {
                          Navigator.of(context).pop();
                          context.push('/sessions/ungrouped');
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.workspacesSectionTitle,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.workspaceCreateTitle,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.add, color: c.textPrimary),
                              onPressed: () {
                                Navigator.of(context).pop();
                                context.push('/workspaces/new');
                              },
                            ),
                          ],
                        ),
                      ),
                      for (final ws in list)
                        _SidebarWorkspace(
                          workspace: ws,
                          expanded: ws.workspaceId == expanded,
                          onOpen: () {
                            ref
                                .read(sharedPreferencesProvider)
                                .setString(
                                  'workspace.last_opened',
                                  ws.workspaceId,
                                );
                            Navigator.of(context).pop();
                            context.push('/workspaces/${ws.workspaceId}');
                          },
                          onOpenSession: (sessionId) {
                            Navigator.of(context).pop();
                            context.push('/sessions/$sessionId');
                          },
                          onToggle: () {
                            final next = ws.workspaceId == expanded
                                ? null
                                : ws.workspaceId;
                            setState(() => _expandedId = next);
                            final prefs = ref.read(sharedPreferencesProvider);
                            if (next == null) {
                              prefs.remove('workspace.last_opened');
                            } else {
                              prefs.setString('workspace.last_opened', next);
                            }
                          },
                        ),
                      const SizedBox(height: 12),
                      Divider(color: c.divider),
                      _SidebarNavRow(
                        icon: Icons.computer_outlined,
                        label: l10n.computersTitle,
                        count: workerCount,
                        onTap: () {
                          Navigator.of(context).pop();
                          context.push('/computers');
                        },
                      ),
                      _SidebarNavRow(
                        icon: Icons.qr_code_scanner_rounded,
                        label: l10n.connectComputer,
                        onTap: () {
                          Navigator.of(context).pop();
                          context.push('/activate');
                        },
                      ),
                      if (list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            l10n.workspaceEmpty,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
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
              child: Consumer(
                builder: (context, ref, _) {
                  final auth = ref.watch(authProvider);
                  final profile = ref.watch(profileProvider).asData?.value;
                  final avatarUrl = ref
                      .watch(profileRepositoryProvider)
                      .resolveAvatarUrl(profile?.avatarUrl);
                  final displayName =
                      profile?.displayName?.trim().isNotEmpty == true
                      ? profile!.displayName!.trim()
                      : auth.username ?? l10n.meTitle;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/me');
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: c.surfaceSelected,
                          foregroundImage: avatarUrl.isEmpty
                              ? null
                              // 降采样到 40px×3x 显示尺寸解码（Play Vitals）
                              : ResizeImage(NetworkImage(avatarUrl),
                                  width: 120),
                          child: Text(
                            displayName.trim().isNotEmpty
                                ? displayName
                                      .trim()
                                      .substring(0, 1)
                                      .toUpperCase()
                                : 'U',
                            style: TextStyle(color: c.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                l10n.profileAndSettings,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: c.textSecondary,
                        ),
                      ],
                    ),
                  );
                },
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
    required this.onOpen,
    required this.onOpenSession,
    required this.onToggle,
  });

  final Workspace workspace;
  final bool expanded;
  final VoidCallback onOpen;
  final ValueChanged<String> onOpenSession;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(
      workspaceSessionsProvider(workspace.workspaceId),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      workspace.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: c.textPrimary),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.sessions,
                visualDensity: VisualDensity.compact,
                icon: AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: c.textSecondary,
                  ),
                ),
                onPressed: onToggle,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push(
                            '/sessions/new?workspaceId=${Uri.encodeComponent(workspace.workspaceId)}',
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: Text(l10n.newSession),
                      ),
                      if (sessions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(l10n.noSessions),
                        ),
                      for (final s in sessions)
                        InkWell(
                          onTap: () => onOpenSession(s.sessionId),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 7,
                            ),
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
                                  child: Text(
                                    _sessionTitle(s),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ),
                                Text(
                                  relativeTime(
                                    s.lastActivityAt,
                                    languageCode: Localizations.localeOf(
                                      context,
                                    ).languageCode,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

String _sessionTitle(SessionSummary s) =>
    s.name.isNotEmpty ? s.name : '终端 ${s.sessionId.substring(0, 8)}';

class _SidebarNavRow extends StatelessWidget {
  const _SidebarNavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.count,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return ListTile(
      dense: true,
      minLeadingWidth: 22,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selected: selected,
      selectedTileColor: c.surfaceSelected,
      leading: Icon(icon, size: 20, color: c.textPrimary),
      title: Text(label, style: TextStyle(fontSize: 14, color: c.textPrimary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count != null)
            Text(
              '$count',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          if (!selected) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: c.textSecondary),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
