import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 首次加载小 spinner。
class SmallSpinner extends StatelessWidget {
  const SmallSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        width: 120,
        child: ShadProgress(value: null, color: scheme.primary),
      ),
    );
  }
}

/// 全局 toast（shadcn Sonner 风格）：统一反馈通道，替代 SnackBar。
void showAppToast(BuildContext context, String message, {bool destructive = false}) {
  ShadToaster.of(context).show(
        destructive
            ? ShadToast.destructive(
                title: Text(message, style: const TextStyle(fontSize: 14)),
              )
            : ShadToast(
                title: Text(message, style: const TextStyle(fontSize: 14)),
              ),
      );
}
