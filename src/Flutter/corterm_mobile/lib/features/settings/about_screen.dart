import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
}
