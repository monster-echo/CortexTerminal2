import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 统一页头：shadcn 框架无导航栏组件，用 Scaffold+AppBar 结构件 +
/// ShadTheme 配色集中在此，页面零散样式。
class CortermAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CortermAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle = true,
    this.showLeading = true,
  });

  final String title;

  /// 需要交互（如 Session Switcher）时替代 [title]。
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool showLeading;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.background,
      foregroundColor: scheme.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      automaticallyImplyLeading: showLeading,
      leading: leading,
      title: titleWidget ??
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ShadTheme.of(context).textTheme.large.copyWith(
                  color: scheme.foreground,
                  fontSize: 17,
                ),
          ),
      actions: actions,
      bottom: bottom,
    );
  }
}
