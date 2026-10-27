import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';
import '../layout/adaptive_sheet.dart';

/// Bounded, scrollable sheet shared by forms and confirmations.
Future<T?> showCortermSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showAdaptiveModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: builder(sheetContext),
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
  final confirmed = await showCortermSheetDialog<bool>(
    context: context,
    title: title,
    child: body.isEmpty
        ? null
        : Builder(
            builder: (bodyContext) => Text(
              body,
              style: ShadTheme.of(bodyContext).textTheme.muted.copyWith(
                color: ShadTheme.of(bodyContext).colorScheme.mutedForeground,
              ),
            ),
          ),
    actions: [
      ShadButton.outline(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        child: Text(l10n.cancel),
      ),
      ShadButton.destructive(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
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
