import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import 'app_bar.dart';

/// 顶层壳（对齐 ArkTS ShellScaffold + SidebarContent）：
/// 三大顶层页（首页/Worker/设置）共用 304 宽侧边栏 + 汉堡按钮；
/// 内容区结构：品牌行 → 导航项 → 活跃会话（≤5）→ 分割线 → 底部用户行。
enum ShellTab { home, workers, settings }

class AppShellScaffold extends ConsumerWidget {
  const AppShellScaffold({
    super.key,
    required this.tab,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final ShellTab tab;
  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.background,
      drawer: Drawer(
        width: 304,
        backgroundColor: scheme.secondary,
        child: SafeArea(child: _SidebarContent(selected: tab)),
      ),
      appBar: CortermAppBar(
        title: title,
        // Builder 下沉 context：Scaffold.of 必须从 Scaffold 之下的树里查找。
        leading: Builder(
          builder: (innerContext) => ShadIconButton.ghost(
            foregroundColor: scheme.foreground,
            icon: const Icon(LucideIcons.menu, size: 22),
            onPressed: () => Scaffold.of(innerContext).openDrawer(),
          ),
        ),
        actions: actions,
      ),
      body: body,
    );
  }
}

class _SidebarContent extends ConsumerWidget {
  const _SidebarContent({required this.selected});

  final ShellTab selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(authProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 品牌行。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/branding/icon.png',
                    width: 36, height: 36),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small
                            .copyWith(fontWeight: FontWeight.w600)),
                    Text(l10n.aboutTagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.muted.copyWith(
                            fontSize: 11, color: scheme.mutedForeground)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _NavItem(
          icon: LucideIcons.command,
          label: l10n.homeTitle,
          selected: selected == ShellTab.home,
          onTap: () => _go(context, '/home'),
        ),
        Divider(color: scheme.border, height: 20, indent: 16, endIndent: 16),
        _NavItem(
          icon: LucideIcons.server,
          label: l10n.workersTitle,
          selected: selected == ShellTab.workers,
          onTap: () => _go(context, '/workers'),
        ),
        _NavItem(
          icon: LucideIcons.settings,
          label: l10n.settings,
          selected: selected == ShellTab.settings,
          onTap: () => _go(context, '/settings'),
        ),
        const Spacer(),
        // 底部用户行 → 设置。
        InkWell(
          onTap: () => _go(context, '/settings'),
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: scheme.card),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: scheme.primary,
                  child: Text(
                    _initial(auth.username),
                    style: theme.textTheme.small.copyWith(
                      color: scheme.primaryForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(auth.username ?? l10n.unknown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.small
                              .copyWith(fontWeight: FontWeight.w500)),
                      Text(l10n.account,
                          style: theme.textTheme.muted
                              .copyWith(color: scheme.mutedForeground)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _initial(String? username) {
    final u = username?.trim();
    if (u == null || u.isEmpty) return 'U';
    return u.characters.first.toUpperCase();
  }

  void _go(BuildContext context, String location) {
    Navigator.of(context).pop(); // 收起抽屉
    context.go(location);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? scheme.primaryForeground
                        : scheme.mutedForeground),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: theme.textTheme.small.copyWith(
                    fontWeight:
                        selected ? FontWeight.w500 : FontWeight.normal,
                    color: selected
                        ? scheme.primaryForeground
                        : scheme.foreground,
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

