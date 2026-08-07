import 'package:flutter/material.dart';

/// 主操作按钮：胶囊 48dp。`expanded` 时铺满但受 maxWidth 400 约束。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.expanded = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon!, size: 18), const SizedBox(width: 8), Text(label)],
      );
    } else {
      child = Text(label);
    }
    final button = FilledButton(onPressed: onPressed, child: child);
    if (!expanded) return button;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}
