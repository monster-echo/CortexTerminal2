import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';

/// 统一 Bottom Sheet 容器（§66）：shadcn expandable 模式——
/// 默认 50% 屏进入，把手拖动在 25%~100% 之间缩放；16dp 边距 + 底部 safe area。
/// 底层走 shadcn 框架的 showShadSheet；各 sheet builder 只写内容。
Future<T?> showCortermSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showShadSheet<T>(
    context: context,
    builder: (sheetContext) {
      // shadcn 默认 expandable 模式：initialSize 0.5 / minSize 0.25 /
      // maxSize 1.0（占屏比），自带拖拽把手，把手拖动缩放、可吸附；
      // 各 sheet builder 只写内容。高度全部交给组件内部，不再外挂约束。
      final content = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: builder(sheetContext),
      );

      final sheet = ShadSheet(
        // expandable 模式下 sheet 高度由把手拖动的占屏比决定，
        // 内容高度约束交给组件内部，不再外挂 minHeight/maxHeight。
        // 关闭手段：下滑到底（minSize 以下继续拖）/ 点遮罩（barrierDismissible）。
        expandable: true,
        // 右上角 ✕ 与头部主操作按钮叠位，去掉。
        closeIcon: const SizedBox.shrink(),
        // 必须关掉 dialog 内建 SafeArea：sheet 底部对齐，它会把「顶部」inset
        // 也加进盒子，在 sheet 顶部撑出大片空白（iPhone 上约 59pt + padding）。
        useSafeArea: false,
        // 边距由容器 content 统一提供（16dp）。
        padding: EdgeInsets.zero,
        // shadcn 的 sheet route 不带 Material 祖先；InkWell/ListTile 类行组件需要它。
        // MaterialType.transparency 是纯渲染层原语，不引入 Material 视觉。
        child: Material(
          type: MaterialType.transparency,
          // 底部 safe area 只在这里消费一次；再 removePadding，让各 sheet
          // 内容里已有的 SafeArea 变成 no-op，避免底部 inset 叠两层。
          child: SafeArea(
            top: false,
            child: MediaQuery.removePadding(
              context: sheetContext,
              removeTop: true,
              removeBottom: true,
              child: content,
            ),
          ),
        ),
      );
      return sheet;
    },
  );
}

/// Sheet 内的节标题（如 RUNNING / RECENT）。
class SheetSectionHeader extends StatelessWidget {
  const SheetSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
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

/// 危险操作确认 Dialog（§67/§28）：仅用于必须立即决策的危险确认。
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showCortermSheetDialog<bool>(
    context: context,
    title: title,
    child: body.isEmpty
        ? null
        : Builder(
            builder: (bodyContext) => Text(
              body,
              style: ShadTheme.of(bodyContext)
                  .textTheme
                  .muted
                  .copyWith(color: ShadTheme.of(bodyContext).colorScheme.mutedForeground),
            ),
          ),
    actions: [
      ShadButton.outline(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(l10n.cancel),
      ),
      ShadButton.destructive(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(confirmLabel),
      ),
    ],
  );
  return confirmed ?? false;
}

/// 居中 Dialog 的移动端形态：同样的「标题 + 内容 + 按钮行」从底部滑出，
/// 拇指可达、支持下滑关闭。移动端所有弹层一律走 sheet，不再用居中 Dialog。
///
/// [actions] 里的按钮用调用方的 context `Navigator.pop(context, value)`
/// 返回值，由本函数透传给调用方。
Future<T?> showCortermSheetDialog<T>({
  required BuildContext context,
  required String title,
  Widget? child,
  List<Widget> actions = const [],
}) {
  return showCortermSheet<T>(
    context: context,
    builder: (sheetContext) {
      final theme = ShadTheme.of(sheetContext);
      // 边距由 showCortermSheet 统一提供（16dp）。按钮按移动端惯例
      // 全宽纵向堆叠（48dp 触控目标），不做右对齐小按钮。
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.large.copyWith(
              color: theme.colorScheme.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (child != null) ...[const SizedBox(height: 16), child],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: actions,
            ),
          ],
        ],
      );
    },
  );
}
