import 'package:flutter/material.dart';

/// 键值对卡片：标题 + 若干 (label, value) 行。用于 Dashboard 的统计区。
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.title, required this.items});

  final String title;
  final List<(String label, String value)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
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
                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ),
                    Expanded(
                      child: Text(value, style: textTheme.bodyMedium?.copyWith(fontSize: 14)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
