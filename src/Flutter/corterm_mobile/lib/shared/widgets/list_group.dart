import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 设置/诊断/Worker 页共用的「分组列表」原语（shadcn 卡片组风格）：
/// [AppGroupCard] = 圆角卡片容器；[AppRow] = 单行（图标 + 标签 + 右侧值/控件）。
/// 之前 settings/workers/diagnostics 三处各写一份，属重复代码，统一到这。
class AppGroupHeader extends StatelessWidget {
  const AppGroupHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Text(
        label,
        style: theme.textTheme.small.copyWith(
          color: theme.colorScheme.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AppGroupCard extends StatelessWidget {
  const AppGroupCard({
    super.key,
    required this.children,
    // 页面里默认撑满剩余高度；sheet 等 Column(min) 场景传 MainAxisSize.min，
    // 否则卡片会被 loose bounded 约束撑到 maxHeight。
    this.mainAxisSize = MainAxisSize.max,
  });

  final List<Widget> children;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: mainAxisSize, children: children),
    );
  }
}

class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.destructive = false,
    this.chevron = false,
    this.trailing,
    this.valueColor,
    this.leadingWidget,
    this.contentPadding,
  });

  final IconData? icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;
  final bool chevron;
  final Widget? trailing;
  final Color? valueColor;

  /// 需要非图标 leading（如状态点）时替代 [icon]。
  final Widget? leadingWidget;

  /// 覆盖 ListTile 默认 16 水平内边距（sheet 内已带 padding 的容器传 [EdgeInsets.zero]）。
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final color = destructive ? scheme.destructive : null;
    final valueText = (value == null || value!.isEmpty)
        ? null
        : Text(
            value!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.muted
                .copyWith(fontSize: 13, color: valueColor ?? scheme.mutedForeground),
          );
    // ListTile 的底色/水波纹画在最近的 Material 祖先上；AppGroupCard 的
    // DecoratedBox 会遮住它们，所以自带一层透明 Material。
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        minVerticalPadding: 14,
        contentPadding: contentPadding,
        iconColor: color ?? scheme.mutedForeground,
        textColor: color,
        leading: leadingWidget ?? Icon(icon, size: 20),
        title: Text(
          label,
          style: theme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: color ?? scheme.foreground,
          ),
        ),
        subtitle: valueText,
        trailing: trailing ??
            (chevron
                ? Icon(LucideIcons.chevronRight, size: 20, color: scheme.mutedForeground)
                : null),
        onTap: onTap,
      ),
    );
  }
}
