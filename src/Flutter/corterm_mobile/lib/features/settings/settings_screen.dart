import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/storage/app_preferences.dart';
import '../../features/sessions/data/sessions_providers.dart';
import 'data/preferences_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/app_bar.dart';
import '../../shared/widgets/list_group.dart';
import '../../shared/widgets/sheets_and_dialogs.dart';
import '../../shared/widgets/states.dart';

/// 法律文档路由参数。
enum LegalRoute { privacy, terms }

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// Settings（§50，loficompanion 分组卡片风格）：
/// 账户 / 应用偏好（外观·语言·终端字号）/ 连接 / 协议与政策 / 安全 / 关于 / 危险区（退出·注销）。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);
    final localeTag = ref.watch(localeProvider);
    final fontSize = ref.watch(fontSizeProvider);
    final gatewayInfo = ref.watch(gatewayInfoProvider);
    final scheme = ShadTheme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        title: l10n.settings,
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ---- 账户 ----
          AppGroupHeader(l10n.account),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.user,
              label: auth.username ?? l10n.unknown,
              value: l10n.account,
            ),
            AppRow(
              icon: LucideIcons.userCog,
              label: l10n.profileTitle,
              chevron: true,
              onTap: () => context.push('/settings/profile'),
            ),
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

          // ---- 应用偏好 ----
          AppGroupHeader(l10n.appearance),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.contrast,
              label: l10n.appearance,
              trailing: ShadSelect<ThemeMode>(
                initialValue: themeMode,
                options: [
                  ShadOption(value: ThemeMode.system, child: Text(l10n.appearanceSystem)),
                  ShadOption(value: ThemeMode.light, child: Text(l10n.appearanceLight)),
                  ShadOption(value: ThemeMode.dark, child: Text(l10n.appearanceDark)),
                ],
                selectedOptionBuilder: (context, value) => Text(switch (value) {
                  ThemeMode.light => l10n.appearanceLight,
                  ThemeMode.dark => l10n.appearanceDark,
                  ThemeMode.system => l10n.appearanceSystem,
                }),
                onChanged: (v) =>
                    v == null ? null : ref.read(themeModeProvider.notifier).set(v),
              ),
            ),
            AppRow(
              icon: LucideIcons.globe,
              label: l10n.language,
              trailing: ShadSelect<String>(
                initialValue: localeTag ?? '',
                options: [
                  const ShadOption(value: '', child: Text('System')),
                  const ShadOption(value: 'en', child: Text('English')),
                  const ShadOption(value: 'zh', child: Text('简体中文')),
                ],
                selectedOptionBuilder: (context, value) => Text(switch (value) {
                  'en' => l10n.languageEnglish,
                  'zh' => l10n.languageChinese,
                  _ => l10n.languageSystem,
                }),
                onChanged: (v) => ref.read(localeProvider.notifier).set(v),
              ),
            ),
            AppRow(
              icon: LucideIcons.monitorSmartphone,
              label: l10n.keepScreenAwake,
              trailing: ShadSwitch(
                value: ref.watch(keepAwakeProvider),
                onChanged: (v) => ref.read(keepAwakeProvider.notifier).set(v),
              ),
            ),
            AppRow(
              icon: LucideIcons.type,
              label: l10n.terminalFontSize,
              value: l10n.fontSizeFmt(fontSize),
              trailing: SizedBox(
                width: 140,
                child: ShadSlider(
                  initialValue: fontSize,
                  min: AppPreferences.minFontSize,
                  max: AppPreferences.maxFontSize,
                  divisions: (AppPreferences.maxFontSize - AppPreferences.minFontSize).round(),
                  onChanged: (v) => ref.read(fontSizeProvider.notifier).set(v),
                ),
              ),
            ),
            _ScrollbackRow(),
          ]),

          // ---- 设备接入 ----
          AppGroupHeader(l10n.deviceAccess),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.scanLine,
              label: l10n.activateTitle,
              chevron: true,
              onTap: () => context.push('/activate'),
            ),
          ]),

          // ---- 协议与政策 ----
          AppGroupHeader(l10n.legal),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.lock,
              label: l10n.privacyPolicy,
              chevron: true,
              onTap: () => context.push('/legal/${LegalRoute.privacy.name}'),
            ),
            AppRow(
              icon: LucideIcons.bookOpen,
              label: l10n.termsOfService,
              chevron: true,
              onTap: () => context.push('/legal/${LegalRoute.terms.name}'),
            ),
          ]),

          // ---- 安全 ----
          AppGroupHeader(l10n.security),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.keyRound,
              label: l10n.changePassword,
              chevron: true,
              onTap: () => _changePassword(context, ref),
            ),
          ]),

          // ---- 关于 ----
          AppGroupHeader(l10n.about),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.info,
              label: l10n.appVersion,
              value: ref.watch(appVersionProvider).valueOrNull ?? '…',
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
            AppRow(
              icon: LucideIcons.fileText,
              label: l10n.aboutTagline,
            ),
          ]),

          const SizedBox(height: 16),
          // ---- 危险区：退出登录 / 注销账号 ----
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.logOut,
              label: l10n.logout,
              onTap: () => _logout(context, ref),
            ),
            AppRow(
              icon: LucideIcons.trash2,
              label: l10n.deleteAccount,
              destructive: true,
              onTap: () => _deleteAccount(context, ref),
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

  /// 注销账号（App Store 硬性要求）：强确认 → DELETE /api/me/account → 清凭据回登录页。
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.deleteAccountConfirmTitle,
      body: l10n.deleteAccountConfirmBody,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
    } finally {
      // 服务端已删除（或网络失败时用户明确要求过注销）——本地凭据一律清除。
      if (context.mounted) {
        await ref.read(authProvider.notifier).logout();
      }
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(l10n.changePassword),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.save),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInputFormField(
              controller: current,
              label: Text(l10n.currentPassword),
              placeholder: Text(l10n.currentPassword),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            ShadInputFormField(
              controller: next,
              label: Text(l10n.newPassword),
              placeholder: Text(l10n.newPassword),
              obscureText: true,
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: current.text,
            newPassword: next.text,
          );
      if (context.mounted) {
        showAppToast(context, l10n.passwordChanged);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '$e', destructive: true);
      }
    }
  }
}

/// 服务端 scrollback 配额（Segment 选择，对齐 MAUI 设置页）。
/// 控制 Worker 重放窗口；客户端 xterm 缓冲恒为 64000 行。
class _ScrollbackRow extends ConsumerWidget {
  static const _options = <int, String>{
    524288: '512K',
    1048576: '1M',
    2097152: '2M',
    5242880: '5M',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pref = ref.watch(scrollbackPreferenceProvider);

    return AppRow(
      icon: LucideIcons.history,
      label: l10n.scrollbackQuota,
      trailing: pref.when(
        loading: () => const SizedBox(
          width: 14,
          height: 14,
          child: ShadProgress(value: null),
        ),
        error: (e, _) => Text('—', style: TextStyle(color: ShadTheme.of(context).colorScheme.mutedForeground)),
        data: (p) {
          // 服务端可能存有非预设值（web 端设置过）：如实展示，不冒充预设档位。
          final options = Map<int, String>.of(_options);
          if (!options.containsKey(p.maxBytes)) {
            options[p.maxBytes] =
                p.maxBytes % 1048576 == 0 ? '${p.maxBytes ~/ 1048576}M' : '${p.maxBytes ~/ 1024}K';
          }
          return ShadSelect<int>(
            initialValue: p.maxBytes,
            options: [
              for (final entry in options.entries)
                ShadOption(value: entry.key, child: Text(entry.value)),
            ],
            selectedOptionBuilder: (context, value) => Text(options[value] ?? '$value'),
            onChanged: (v) async {
              if (v == null || v == p.maxBytes) return;
              try {
                await ref.read(preferencesRepositoryProvider).updateScrollback(maxBytes: v);
                ref.invalidate(scrollbackPreferenceProvider);
                if (context.mounted) showAppToast(context, l10n.saved);
              } catch (e) {
                if (context.mounted) {
                  showAppToast(context, '$e', destructive: true);
                }
              }
            },
          );
        },
      ),
    );
  }
}
