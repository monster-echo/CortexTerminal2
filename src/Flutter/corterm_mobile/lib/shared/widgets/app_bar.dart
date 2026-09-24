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
    this.leadingWidth,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String title;

  /// 需要交互（如 Session Switcher）时替代 [title]。
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool showLeading;

  /// 与右侧 actions 对称时指定（默认 AppBar 56）。
  final double? leadingWidth;

  /// 终端页等需要跟随终端配色的场景覆盖默认 ShadTheme 背景/前景。
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return AppBar(
      backgroundColor: backgroundColor ?? scheme.background,
      foregroundColor: foregroundColor ?? scheme.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      automaticallyImplyLeading: showLeading,
      leading: leading,
      leadingWidth: leadingWidth,
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
      // M3 默认 actionsPadding 为 0（贴屏边）；补 8 让图标视觉边距 = 8+8=16，
      // 与内容区 16 缩进对齐（Material 上游 TODO 也计划改为 end: 8）。
      actionsPadding: const EdgeInsetsDirectional.only(end: 8),
      bottom: bottom,
    );
  }
}
