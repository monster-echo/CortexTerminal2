import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/corterm_theme.dart';
import '../../core/models/session.dart';
import '../../core/storage/app_preferences.dart';
import '../../shared/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/layout/adaptive_window.dart';
import '../sessions/data/sessions_providers.dart';
import '../workspaces/data/workspace_providers.dart';

class WorkspacePaneScope extends InheritedWidget {
  const WorkspacePaneScope({
    super.key,
    required this.visible,
    this.available = false,
    required super.child,
  });

  final bool visible;
  final bool available;
  static bool isAvailable(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspacePaneScope>()
          ?.available ??
      false;

  static bool isVisible(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspacePaneScope>()
          ?.visible ??
      false;

  @override
  bool updateShouldNotify(WorkspacePaneScope oldWidget) =>
      visible != oldWidget.visible || available != oldWidget.available;
}

/// Keep the same Navigator in the same tree position while resizing. Folding
/// changes column widths, not routes, terminal attachments or file-page state.
class AdaptiveWorkspaceShell extends ConsumerStatefulWidget {
  const AdaptiveWorkspaceShell({
    super.key,
    required this.child,
    required this.location,
    this.navigationShell,
  });

  final StatefulNavigationShell? navigationShell;
  final Widget child;
  final Uri location;

  @override
  ConsumerState<AdaptiveWorkspaceShell> createState() =>
      _AdaptiveWorkspaceShellState();
}

class _AdaptiveWorkspaceShellState
    extends ConsumerState<AdaptiveWorkspaceShell> {
  Future<void> _toggleDirectory() async {
    try {
      await ref
          .read(directoryCollapsedProvider.notifier)
          .set(!ref.read(directoryCollapsedProvider));
    } catch (error) {
      if (mounted) showAppToast(context, '$error', destructive: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(directoryCollapsedProvider);
    final window = WindowLayoutScope.of(context);
    final media = MediaQuery.of(context);
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final native = Theme.of(context).platform == TargetPlatform.iOS;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxWidth - media.padding.horizontal;
        final fold = window.verticalDivision;
        // 280 points for navigation + at least 440 for a usable terminal/form.
        var primary = usable >= 760 ? 280.0 + media.padding.left : 0.0;
        var gap = primary > 0 ? 1.0 : 0.0;
        if (fold != null) {
          final before = fold.left - media.padding.left;
          final after = constraints.maxWidth - fold.right - media.padding.right;
          if (before >= 260 && after >= 320) {
            primary = fold.left;
            gap = fold.width;
          } else {
            primary = 0;
            gap = 0;
          }
        }
        if (widget.navigationShell != null &&
            widget.navigationShell!.currentIndex != 0) {
          primary = 0;
          gap = 0;
        }
        final canShow = primary > 0;
        final visible = canShow && !collapsed;
        if (canShow && collapsed) {
          primary = 48.0 + media.padding.left;
          // A reserved division is still excluded when the directory is hidden.
          gap = fold == null ? 1 : fold.right - primary;
        }
        final pane = Rect.fromLTWH(
          primary + gap,
          0,
          constraints.maxWidth - primary - gap,
          constraints.maxHeight,
        );
        final padding = media.padding.copyWith(
          left: canShow ? 0 : media.padding.left,
        );
        return WorkspacePaneScope(
          visible: visible,
          available: canShow,
          child: Material(
            color: colors.background,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: primary,
                  child: visible
                      ? Semantics(
                          container: true,
                          explicitChildNodes: true,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top:
                                  platform.ToolbarChromeScope.maybeOf(context)
                                          ?.hostsDuoControls ==
                                      true
                                  ? platform.kDuoTitleBandHeight
                                  : kToolbarHeight,
                            ),
                            child: _WorkspaceNavigator(
                              location: widget.location,
                              onCollapse: _toggleDirectory,
                            ),
                          ),
                        )
                      : canShow
                      ? SafeArea(
                          right: false,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 56),
                              child: IconButton(
                                tooltip:
                                    Localizations.localeOf(context)
                                            .languageCode ==
                                        'zh'
                                    ? '显示工作区目录'
                                    : 'Show workspace sidebar',
                                icon: const Icon(Icons.menu_open),
                                onPressed: _toggleDirectory,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
                SizedBox(
                  width: gap,
                  child: ColoredBox(color: colors.divider),
                ),
                Expanded(
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: WindowLayoutScope(
                      layout: canShow ? window.forPane(pane) : window,
                      child: MediaQuery(
                        data: media.copyWith(
                          size: pane.size,
                          padding: padding,
                          viewPadding: media.viewPadding.copyWith(
                            left: canShow ? 0 : media.viewPadding.left,
                          ),
                        ),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    final shell = widget.navigationShell;
    if (shell == null) return content;
    return platform.AdaptiveScaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: colors.background,
      body: content,
      bottomNavigationBar: platform.AdaptiveBottomNavigationBar(
        selectedIndex: shell.currentIndex,
        onTap: (index) => shell.goBranch(index),
        items: [
          platform.AdaptiveNavigationDestination(
            icon: native ? 'square.grid.2x2' : Icons.grid_view_outlined,
            label: l10n.workspacesSectionTitle,
          ),
          platform.AdaptiveNavigationDestination(
            icon: native ? 'desktopcomputer' : Icons.computer_outlined,
            label: l10n.computersTitle,
          ),
          platform.AdaptiveNavigationDestination(
            icon: native ? 'person.crop.circle' : Icons.person_outline,
            label: l10n.meTitle,
          ),
        ],
      ),
    );
  }
}

class _WorkspaceNavigator extends ConsumerWidget {
  const _WorkspaceNavigator({required this.location, required this.onCollapse});

  final VoidCallback onCollapse;

  final Uri location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final path = location.path;
    final sessions = ref.watch(sessionsProvider);
    final list = sessions.asData?.value ?? const <SessionSummary>[];
    final workspaces = ref.watch(workspacesProvider);
    final workers = ref.watch(workersProvider).asData?.value ?? const [];
    final selectedSession = path.startsWith('/sessions/')
        ? list
              .where((session) => path == '/sessions/${session.sessionId}')
              .firstOrNull
        : null;
    final selectedWorkspaceId =
        selectedSession?.workspaceId ??
        (path.startsWith('/workspaces/')
            ? location.pathSegments.elementAtOrNull(1)
            : location.queryParameters['workspaceId']);

    void go(String route) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (route == '/home') {
        context.go(route);
      } else if (route != location.toString()) {
        context.push(route);
      }
    }

    Widget row({
      required IconData icon,
      required String label,
      required String route,
      String? subtitle,
      bool selected = false,
      Widget? trailing,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? c.surfaceSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          minLeadingWidth: 20,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(icon, size: 20, color: c.textPrimary),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
          trailing: trailing,
          onTap: () => go(route),
        ),
      ),
    );

    return SafeArea(
      right: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.workspacesSectionTitle,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: Localizations.localeOf(context).languageCode == 'zh'
                      ? '隐藏工作区目录'
                      : 'Hide workspace sidebar',
                  icon: const Icon(Icons.chevron_left, size: 22),
                  onPressed: onCollapse,
                ),
                IconButton(
                  tooltip: l10n.workspaceCreateTitle,
                  icon: const Icon(Icons.add, size: 22),
                  onPressed: () => context.push('/workspaces/new'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const PageStorageKey('expanded-workspace-navigation'),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                row(
                  icon: Icons.grid_view_outlined,
                  label: l10n.workspacesSectionTitle,
                  route: '/home',
                  selected: path == '/home',
                ),
                row(
                  icon: Icons.terminal_outlined,
                  label: l10n.ungroupedSessions,
                  route: '/sessions/ungrouped',
                  selected: path == '/sessions/ungrouped',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                  child: Text(
                    l10n.workspacesSectionTitle,
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ),
                ...workspaces.when(
                  loading: () => [const LinearProgressIndicator()],
                  error: (error, _) => [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '$error',
                        style: TextStyle(color: c.danger, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(workspacesProvider),
                      child: Text(l10n.retry),
                    ),
                  ],
                  data: (items) => [
                    for (final workspace in items) ...[
                      row(
                        icon: Icons.folder_outlined,
                        label: workspace.displayName,
                        subtitle: workers
                            .where(
                              (worker) => worker.workerId == workspace.workerId,
                            )
                            .map((worker) => worker.displayName)
                            .firstOrNull,
                        route: '/workspaces/${workspace.workspaceId}',
                        selected:
                            selectedWorkspaceId == workspace.workspaceId &&
                            selectedSession == null,
                      ),
                      if (selectedWorkspaceId == workspace.workspaceId) ...[
                        for (final session
                            in list
                                .where(
                                  (session) =>
                                      session.workspaceId ==
                                      workspace.workspaceId,
                                )
                                .toList()
                              ..sort(
                                (a, b) => b.lastActivityAt.compareTo(
                                  a.lastActivityAt,
                                ),
                              ))
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: 16,
                            ),
                            child: row(
                              icon: Icons.terminal,
                              label: session.displayName,
                              route: '/sessions/${session.sessionId}',
                              selected:
                                  selectedSession?.sessionId ==
                                  session.sessionId,
                              trailing: Icon(
                                Icons.circle,
                                size: 6,
                                color: session.status.isAlive
                                    ? c.success
                                    : c.textSecondary,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 16),
                          child: row(
                            icon: Icons.add,
                            label: l10n.newSession,
                            route:
                                '/sessions/new?workspaceId=${Uri.encodeComponent(workspace.workspaceId)}',
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                if (sessions.hasError)
                  TextButton(
                    onPressed: () => ref.invalidate(sessionsProvider),
                    child: Text(l10n.sessionsLoadRetry),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: c.divider),
          row(
            icon: Icons.search,
            label: MaterialLocalizations.of(context).searchFieldLabel,
            route: '/search',
          ),
        ],
      ),
    );
  }
}
