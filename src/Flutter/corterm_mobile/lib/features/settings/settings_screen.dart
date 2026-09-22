import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/list_group.dart';
import '../../shared/widgets/sheets_and_dialogs.dart';

/// 法律文档路由参数。
enum LegalRoute { privacy, terms }

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// Settings 根页（§50）：用页面深度做减法 —— 根页只留导航入口，
/// 细项全部下沉二级页（通用 / 安全 / 关于 / 帮助），底部保留危险区。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);

    return AppShellScaffold(
      tab: ShellTab.settings,
      title: l10n.settings,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ---- 账户 ----
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.user,
              label: auth.username ?? l10n.profileTitle,
              value: l10n.profileTitle,
              chevron: true,
              onTap: () => context.push('/settings/profile'),
            ),
          ]),

          // ---- 通用 / 安全 / 设备 ----
          AppGroupHeader(l10n.appearance),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.settings,
              label: l10n.appearance,
              chevron: true,
              onTap: () => context.push('/settings/preferences'),
            ),
          ]),
          AppGroupHeader(l10n.security),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.keyRound,
              label: l10n.changePassword,
              chevron: true,
              onTap: () => context.push('/settings/security'),
            ),
          ]),
          AppGroupHeader(l10n.deviceAccess),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.scanLine,
              label: l10n.activateTitle,
              chevron: true,
              onTap: () => context.push('/activate'),
            ),
          ]),

          // ---- 帮助 ----
          AppGroupHeader(l10n.supportTitle),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.headphones,
              label: l10n.supportTitle,
              chevron: true,
              onTap: () => context.push('/settings/support'),
            ),
            AppRow(
              icon: LucideIcons.messageSquare,
              label: l10n.feedbackTitle,
              chevron: true,
              onTap: () => context.push('/settings/feedback'),
            ),
          ]),

          // ---- 关于 ----
          AppGroupHeader(l10n.about),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.info,
              label: l10n.about,
              chevron: true,
              onTap: () => context.push('/settings/about'),
            ),
          ]),

          const SizedBox(height: 16),
          // ---- 危险区：退出登录 ----
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.logOut,
              label: l10n.logout,
              onTap: () => _logout(context, ref),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.logoutConfirm,
      body: '',
      confirmLabel: l10n.logout,
      destructive: true,
    );
    if (confirmed) {
      await ref.read(authProvider.notifier).logout();
    }
  }
}
