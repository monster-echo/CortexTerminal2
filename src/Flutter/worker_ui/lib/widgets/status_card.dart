import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 键值对卡片：标题 + 若干 (label, value) 行。用于 Dashboard 的统计区。
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.title, required this.items});

  final String title;
  final List<(String label, String value)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return ShadCard(
      title: Text(title),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          for (final (label, value) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      label,
                      style: TextStyle(color: scheme.mutedForeground, fontSize: 14),
                    ),
                  ),
                  Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: scheme.foreground))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
