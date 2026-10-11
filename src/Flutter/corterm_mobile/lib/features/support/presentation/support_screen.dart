import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../data/support_repository.dart';

/// 唯一客服渠道：飞书。有效邀请链接可直接生成二维码，避免远程图片失效。
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final c = colorsOf(context);
    final info = ref.watch(supportInfoProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: CortermAppBar(
        title: l10n.supportTitle,
        leading: ShadIconButton.ghost(
          foregroundColor: c.textPrimary,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: info.when(
        loading: () => const Center(child: ShadProgress(value: null)),
        error: (e, _) => ErrorState(message: '$e'),
        data: (data) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            if (data.feishuGroup != null)
              _GroupCard(
                icon: LucideIcons.messageCircle,
                title: data.feishuGroup!.name.isNotEmpty
                    ? data.feishuGroup!.name
                    : l10n.feishuGroup,
                subtitle: data.feishuGroup!.url ?? '',
                qrCodeUrl: data.feishuGroup!.qrCodeUrl,
                onCopy:
                    data.feishuGroup!.url == null ||
                        data.feishuGroup!.url!.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(
                          ClipboardData(text: data.feishuGroup!.url!),
                        );
                        showAppToast(context, l10n.copied);
                      },
                onOpen:
                    data.feishuGroup!.url == null ||
                        data.feishuGroup!.url!.isEmpty
                    ? null
                    : () => launchUrl(
                        Uri.parse(data.feishuGroup!.url!),
                        mode: LaunchMode.externalApplication,
                      ),
              ),
            if (data.feishuGroup == null)
              Text(
                Localizations.localeOf(context).languageCode == 'zh'
                    ? '飞书支持群暂不可用，请稍后重试。'
                    : 'The Feishu support group is temporarily unavailable.',
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.qrCodeUrl,
    required this.onCopy,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String qrCodeUrl;
  final VoidCallback? onCopy;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty || qrCodeUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: () => _previewQr(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorsOf(context).onEmphasis,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _qr(context, 192),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onCopy != null)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: onCopy,
                    child: Text(l10n.copy),
                  ),
                if (onOpen != null) ...[
                  const SizedBox(width: 8),
                  ShadButton.secondary(
                    size: ShadButtonSize.sm,
                    onPressed: onOpen,
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '加入飞书群'
                          : 'Join Feishu group',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _previewQr(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);
    showCortermSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorsOf(context).onEmphasis,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _qr(context, 280),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.small.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.muted.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: 12),
              ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qr(BuildContext context, double size) {
    if (subtitle.isNotEmpty) {
      return QrImageView(
        data: subtitle,
        size: size,
        backgroundColor: CortermColors.light.surface,
        eyeStyle: QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: CortermColors.light.textPrimary,
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: CortermColors.light.textPrimary,
        ),
      );
    }
    return Image.network(
      qrCodeUrl,
      width: size,
      height: size,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: Icon(LucideIcons.qrCode, color: colorsOf(context).textSecondary),
      ),
    );
  }
}
