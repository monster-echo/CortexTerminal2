import 'package:flutter/material.dart';

import 'sheets_and_dialogs.dart';

/// Keeps edits in the owning route until the user explicitly discards them.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.busy = false,
  });
  final bool dirty;
  final bool busy;
  final Widget child;
  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _allowPop = false;
  bool _asking = false;
  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop || (!widget.dirty && !widget.busy),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || widget.busy || _asking) return;
      _asking = true;
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      final discard = await showConfirmDialog(
        context: context,
        title: zh ? '放弃未保存的修改？' : 'Discard unsaved changes?',
        body: zh
            ? '返回后，本页尚未保存的内容将丢失。'
            : 'Your unsaved changes on this page will be lost.',
        confirmLabel: zh ? '放弃修改' : 'Discard changes',
        destructive: true,
      );
      _asking = false;
      if (!mounted || !discard) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(result);
      });
    },
    child: widget.child,
  );
}
