import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';

/// 统一 Bottom Sheet 容器（§66）：底部滑入、可拖拽、safe area。
/// 底层走 shadcn 框架的 showShadSheet；[builder] 里的 content 自带 padding。
/// [maxHeightFactor] 控制最大高度占屏比例（默认 85%）。
/// [minHeightFactor] 控制最小高度占屏比例；设置后 sheet 至少占这么高（Flutter
/// showModalBottomSheet 的 isScrollControlled 固定高度模式）。
/// [showDragHandle] 在 sheet 顶部绘制拖拽把手（Material 惯例），默认显示。
Future<T?> showCortermSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  double maxHeightFactor = 0.85,
  double? minHeightFactor,
  bool showDragHandle = true,
}) {
  return showShadSheet<T>(
    context: context,
    builder: (sheetContext) {
      final size = MediaQuery.sizeOf(sheetContext);
      final theme = ShadTheme.of(sheetContext);
      final minH = (minHeightFactor ?? 0) * size.height;
      final maxH = maxHeightFactor * size.height;

      // 高度策略：minHeight 场景给固定高度（Column+Expanded 数学上成立）；
      // 其余场景 Column min + Flexible(loose)，内容自适应且被 maxHeight 封顶，
      // 在任意视口（宽屏 Chrome / iPad / 手机）下都不会产生无界约束。
      final Widget content = minH > 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDragHandle) _dragHandle(theme),
                Expanded(child: builder(sheetContext)),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDragHandle) _dragHandle(theme),
                Flexible(
                  fit: FlexFit.loose,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: builder(sheetContext),
                  ),
                ),
              ],
            );

      return ShadSheet(
        constraints: BoxConstraints(
          maxHeight: maxH,
          minHeight: minH,
        ),
        // shadcn 的 sheet route 不带 Material 祖先；InkWell/ListTile 类行组件需要它。
        // MaterialType.transparency 是纯渲染层原语，不引入 Material 视觉。
        child: Material(
          type: MaterialType.transparency,
          child: content,
        ),
      );
    },
  );
}

Widget _dragHandle(ShadThemeData theme) {
  return Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.border,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
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
  final confirmed = await showShadDialog<bool>(
    context: context,
    builder: (context) => ShadDialog.alert(
      title: Text(title),
      description: body.isEmpty ? null : Text(body),
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
    ),
  );
  return confirmed ?? false;
}
