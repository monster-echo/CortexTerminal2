import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';

/// 空状态（§69）：极简，一个说明 + 一个可选动作。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.hint, this.actionLabel, this.onAction});

  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.p.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.foreground,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.muted.copyWith(color: scheme.mutedForeground),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              ShadButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误状态（§71）：用户可读信息 + Retry。不展示裸异常文本。
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.muted.copyWith(color: theme.colorScheme.foreground),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ShadButton.outline(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 首次加载小 spinner（§70：不用整页 skeleton）。
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

/// 全局 toast（shadcn Sonner 风格）：统一反馈通道，替代散落的 SnackBar。
void showAppToast(BuildContext context, String message, {bool destructive = false}) {
  ShadToaster.of(context).show(
    destructive
        ? ShadToast.destructive(title: Text(message))
        : ShadToast(title: Text(message)),
  );
}
