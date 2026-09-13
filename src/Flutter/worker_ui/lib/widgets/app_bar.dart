import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 统一页头（移植自 corterm_mobile 的 CortermAppBar）：shadcn 框架无导航栏
/// 组件，用 Scaffold+AppBar 结构件 + ShadTheme 配色集中在此，页面零散样式。
class WorkerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WorkerAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
  }) : assert(title != null || titleWidget != null);

  final String? title;

  /// 需要特殊排版（如 monospace sessionId）时替代 [title]。
  final Widget? titleWidget;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.background,
      foregroundColor: scheme.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: titleWidget ??
          Text(
            title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.foreground,
            ),
          ),
      actions: actions,
    );
  }
}
