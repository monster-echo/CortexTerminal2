import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';

/// 统一 Bottom Sheet 容器（§66）：底部滑入、可拖拽、safe area、最大 85% 屏高。
/// 底层走 shadcn 框架的 showShadSheet；[builder] 里的 content 自带 padding。
Future<T?> showCortermSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showShadSheet<T>(
    context: context,
    builder: (sheetContext) => ShadSheet(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
      ),
      // shadcn 的 sheet route 不带 Material 祖先；InkWell/ListTile 类行组件需要它。
      // MaterialType.transparency 是纯渲染层原语，不引入 Material 视觉。
      child: Material(
        type: MaterialType.transparency,
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
    final scheme = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: scheme.mutedForeground,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
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
