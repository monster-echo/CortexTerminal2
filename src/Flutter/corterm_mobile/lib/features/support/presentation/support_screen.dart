import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../data/support_repository.dart';

/// 联系客服（对齐 MAUI ContactSupportPage）：QQ 群 / Telegram 群卡片 + 邮箱。
/// 二维码预览大图，保存走系统分享（对齐 MAUI，不申请相册权限）。
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
            if (data.qqGroup != null)
              _GroupCard(
                icon: LucideIcons.messagesSquare,
                title: data.qqGroup!.name,
                subtitle: data.qqGroup!.number ?? '',
                qrCodeUrl: data.qqGroup!.qrCodeUrl,
                onCopy: data.qqGroup!.number == null || data.qqGroup!.number!.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: data.qqGroup!.number!));
                        showAppToast(context, l10n.copied);
                      },
                onOpen: null,
              ),
            if (data.telegramGroup != null)
              _GroupCard(
                icon: LucideIcons.send,
                title: data.telegramGroup!.name,
                subtitle: data.telegramGroup!.url ?? '',
                qrCodeUrl: data.telegramGroup!.qrCodeUrl,
                onCopy: data.telegramGroup!.url == null || data.telegramGroup!.url!.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: data.telegramGroup!.url!));
                        showAppToast(context, l10n.copied);
                      },
                onOpen: data.telegramGroup!.url == null ||
                        data.telegramGroup!.url!.isEmpty
                    ? null
                    : () => launchUrl(
                        Uri.parse(data.telegramGroup!.url!),
                        mode: LaunchMode.externalApplication),
              ),
            if (data.feishuGroup != null)
              _GroupCard(
                icon: LucideIcons.messageCircle,
                title: data.feishuGroup!.name.isNotEmpty
                    ? data.feishuGroup!.name
                    : l10n.feishuGroup,
                subtitle: data.feishuGroup!.url ?? '',
                qrCodeUrl: data.feishuGroup!.qrCodeUrl,
                onCopy: data.feishuGroup!.url == null ||
                        data.feishuGroup!.url!.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: data.feishuGroup!.url!));
                        showAppToast(context, l10n.copied);
                      },
                onOpen: data.feishuGroup!.url == null ||
                        data.feishuGroup!.url!.isEmpty
                    ? null
                    : () => launchUrl(
                        Uri.parse(data.feishuGroup!.url!),
                        mode: LaunchMode.externalApplication),
              ),
            if (data.email.isNotEmpty)
              _GroupCard(
                icon: LucideIcons.mail,
                title: l10n.supportEmail,
                subtitle: data.email,
                qrCodeUrl: '',
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: data.email));
                  showAppToast(context, l10n.copied);
                },
                onOpen: () =>
                    launchUrl(Uri.parse('mailto:${data.email}'), mode: LaunchMode.externalApplication),
              ),
            const SizedBox(height: 24),
            AppRow(
              icon: LucideIcons.messageSquare,
              label: l10n.feedbackTitle,
              chevron: true,
              onTap: () => context.push('/settings/feedback'),
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
                        fontWeight: FontWeight.w600, color: c.textPrimary),
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.muted.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
            if (qrCodeUrl.isNotEmpty) ...[
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
                    child: Image.network(
                      qrCodeUrl,
                      width: 132,
                      height: 132,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => SizedBox(
                        width: 132,
                        height: 132,
                        child: Icon(LucideIcons.qrCode, size: 32, color: c.textSecondary),
                      ),
                    ),
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
                    child: Text(l10n.tunnelOpen),
                  ),
                ],
                if (qrCodeUrl.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ShadButton.secondary(
                    size: ShadButtonSize.sm,
                    onPressed: () => _shareQr(context),
                    child: Text(l10n.supportSaveQr),
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
                child: Image.network(
                  qrCodeUrl,
                  width: 280,
                  height: 280,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: theme.textTheme.small
                      .copyWith(fontWeight: FontWeight.w600, color: c.textPrimary)),
              Text(subtitle,
                  style: theme.textTheme.muted.copyWith(color: c.textSecondary)),
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

  Future<void> _shareQr(BuildContext context) async {
    // 下载二维码到内存 → 系统分享面板（XFile.fromData，web 同样可用；MAUI 同款）。
    final dio = Dio();
    try {
      final res = await dio.get<List<int>>(
        qrCodeUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.statusCode != 200 || res.data == null) {
        throw StateError('QR download failed: HTTP ${res.statusCode}');
      }
      await SharePlus.instance.share(
        ShareParams(files: [
          XFile.fromData(
            Uint8List.fromList(res.data!),
            name: title,
            mimeType: 'image/png',
          ),
        ]),
      );
    } finally {
      dio.close();
    }
  }
}
