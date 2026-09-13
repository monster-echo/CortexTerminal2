import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 区域标题（18 Bold）+ 可选 trailing 操作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.foreground),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
