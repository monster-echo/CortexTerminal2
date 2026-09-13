import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 主操作按钮：48dp 高。`expanded` 时铺满但受 maxWidth 400 约束。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.expanded = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    // shadcn 按钮只认 enabled:，onPressed: null 不会置灰
    final button = ShadButton(
      onPressed: onPressed,
      enabled: onPressed != null,
      leading: icon == null ? null : Icon(icon, size: 18),
      child: Text(label),
    );
    if (!expanded) return button;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}
