import '../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/states.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/corterm_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../features/sessions/data/sessions_providers.dart';
import '../../shared/widgets/list_group.dart';
import 'settings_screen.dart';

/// 安装包名称供其他调用方读取；页面品牌名称使用当前界面的本地化资源。
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
    final c = colorsOf(context);
    final gatewayInfo = ref.watch(gatewayInfoProvider);

    return AdaptivePageScaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 28),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/icon.png',
                    width: 72,
                    height: 72,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.appName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                ref
                    .watch(appVersionProvider)
                    .when(
                      loading: () => const Text('…'),
                      error: (error, _) => TextButton(
                        onPressed: () => ref.invalidate(appVersionProvider),
                        child: Text(l10n.retry),
                      ),
                      data: (version) => TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: version));
                          if (context.mounted) {
                            showAppToast(context, l10n.copied);
                          }
                        },
                        child: Text(version),
                      ),
                    ),
              ],
            ),
          ),
          AppGroupCard(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AboutRow(label: l10n.rateUs, onTap: () => _rateApp(context)),
              _AboutRow(
                label: Localizations.localeOf(context).languageCode == 'zh'
                    ? '开源许可'
                    : 'Open source licenses',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: l10n.appName,
                ),
              ),
              _AboutRow(
                label: l10n.diagnostics,
                onTap: () => context.push('/diagnostics'),
                last: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppGroupHeader(l10n.legal),
          AppGroupCard(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AboutRow(
                label: l10n.privacyPolicy,
                onTap: () => context.push('/legal/privacy'),
              ),
              _AboutRow(
                label: l10n.termsOfService,
                onTap: () => context.push('/legal/terms'),
              ),
              _AboutRow(
                label: Localizations.localeOf(context).languageCode == 'zh'
                    ? '账号注销协议'
                    : 'Account deletion policy',
                onTap: () => context.push('/legal/deletion'),
                last: true,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Column(
              children: [
                Text(
                  l10n.aboutTagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                if (gatewayInfo.valueOrNull?.version case final String version)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${l10n.gatewayVersion} $version',
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
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
        'https://play.google.com/store/apps/details?id=${info.packageName}',
      );
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError(l10n.rateFailed(uri.toString()));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.rateFailed('$e'))));
      }
    }
  }
}

/// About links use quiet, single-line rows; separators describe group membership.
class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.label,
    required this.onTap,
    this.last = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 2,
            ),
            title: Text(
              label,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: 20,
              color: c.textSecondary,
            ),
            onTap: onTap,
          ),
        ),
        if (!last)
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Divider(height: 1, thickness: 0.5, color: c.divider),
          ),
      ],
    );
  }
}
