import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../features/sessions/data/sessions_providers.dart';
import '../../shared/widgets/list_group.dart';
import 'settings_screen.dart';

/// 关于我们（参考页二级页）：App 图标 + 名称 + 版本号居中，
/// 协议/诊断分组卡片，底部标语。
final appNameProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.appName;
});

/// 关于我们页。
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final gatewayInfo = ref.watch(gatewayInfoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SizedBox(height: 32),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/branding/icon.png',
                width: 88,
                height: 88,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              ref.watch(appNameProvider).valueOrNull ?? 'CortexTerminal',
              style: theme.textTheme.small.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.foreground,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              ref.watch(appVersionProvider).valueOrNull ?? '…',
              style: theme.textTheme.muted.copyWith(fontSize: 14),
            ),
          ),
          AppGroupHeader(l10n.legal),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.lock,
              label: l10n.privacyPolicy,
              chevron: true,
              onTap: () => context.push('/legal/privacy'),
            ),
            AppRow(
              icon: LucideIcons.bookOpen,
              label: l10n.termsOfService,
              chevron: true,
              onTap: () => context.push('/legal/terms'),
            ),
          ]),
          AppGroupHeader(l10n.diagnostics),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.star,
              label: l10n.rateUs,
              chevron: true,
              onTap: () => _rateApp(context),
            ),
            AppRow(
              icon: LucideIcons.cloud,
              label: l10n.gatewayVersion,
              value: gatewayInfo.valueOrNull?.version ?? '—',
            ),
            AppRow(
              icon: LucideIcons.bug,
              label: l10n.diagnostics,
              chevron: true,
              onTap: () => context.push('/diagnostics'),
            ),
          ]),
          const SizedBox(height: 32),
          Center(
            child: Text(
              l10n.aboutTagline,
              style: theme.textTheme.muted.copyWith(fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 跳转应用商店评分页：Android → Google Play，iOS → App Store 搜索，
  /// 其余平台 → Play 商店网页版。打不开时 toast 明确报错。
  Future<void> _rateApp(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final info = await PackageInfo.fromPlatform();
    final Uri uri;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      uri = Uri.parse('https://apps.apple.com/search?term=cortexterminal');
    } else {
      uri = Uri.parse(
          'https://play.google.com/store/apps/details?id=${info.packageName}');
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.rateFailed('$e'))),
        );
      }
    }
  }
}
