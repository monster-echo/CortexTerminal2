import 'package:flutter/material.dart';

import '../../app/theme/corterm_theme.dart';

/// Await confirmation and the server response before the owner refreshes its data.
class SwipeDelete extends StatefulWidget {
  const SwipeDelete({
    super.key,
    required this.child,
    required this.title,
    required this.message,
    required this.onDelete,
  });
  final Widget child;
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
    return Dismissible(
      key: ValueKey(widget.key),
      direction: _busy ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        color: c.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: c.onEmphasis),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
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
        if (confirmed != true || !mounted) return false;
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
        // The owner invalidates the authoritative list; never dismiss on failure.
        return false;
      },
      child: widget.child,
    );
  }
}
