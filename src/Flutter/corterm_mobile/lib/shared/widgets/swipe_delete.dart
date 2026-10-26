import '../layout/adaptive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../app/theme/corterm_theme.dart';

/// Await confirmation and the server response before the owner refreshes its data.
class SwipeDelete extends StatefulWidget {
  const SwipeDelete({
    super.key,
    required this.child,
    required this.title,
    required this.message,
    required this.onDelete,
    this.margin = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry margin;
  final String title;
  final String message;
  final Future<void> Function() onDelete;
  @override
  State<SwipeDelete> createState() => _SwipeDeleteState();
}

class _SwipeDeleteState extends State<SwipeDelete> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      padding: widget.margin,
      child: Slidable(
        key: ValueKey(widget.key),
        enabled: !_busy,
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: .22,
          children: [
            SlidableAction(
              onPressed: (context) async {
                final slidableController = Slidable.of(context);
                final confirmed = await showCortermDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(widget.title),
                    content: Text(widget.message),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(zh ? '取消' : 'Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          zh ? '删除' : 'Delete',
                          style: TextStyle(color: c.danger),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                setState(() => _busy = true);
                try {
                  await widget.onDelete();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
                // Keep the row mounted until the owner refreshes its authoritative list.
                slidableController?.close();
              },
              backgroundColor: c.danger,
              foregroundColor: c.onEmphasis,
              icon: Icons.delete_outline,
              label: zh ? '删除' : 'Delete',
              borderRadius: BorderRadius.circular(12),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
