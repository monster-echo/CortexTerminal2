import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/app_strings.dart';

/// 错误提示条（红色），message 为空则不渲染。按 CLAUDE.md：错误必须明确展示，不隐藏。
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    final scheme = ShadTheme.of(context).colorScheme;
    final color = scheme.destructive;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleAlert, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message!,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          if (onRetry != null)
            ShadButton.link(
              onPressed: onRetry,
              child: Text(AppStrings.t(context, 'common.retry')),
            ),
        ],
      ),
    );
  }
}
