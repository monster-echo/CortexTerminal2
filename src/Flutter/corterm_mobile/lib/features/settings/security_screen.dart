import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/list_group.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/sheets_and_dialogs.dart';

/// 安全（设置二级页）：修改密码。
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.security)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.keyRound,
                label: l10n.changePassword,
                chevron: true,
                onTap: () => _changePassword(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.logOut,
                label: l10n.logout,
                onTap: () => _logout(context, ref),
              ),
              AppRow(
                icon: LucideIcons.fileText,
                label: Localizations.localeOf(context).languageCode == 'zh'
                    ? '账户注销协议'
                    : 'Account deletion policy',
                chevron: true,
                onTap: () => context.push('/legal/deletion'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ---- 危险区：注销账号（App Store 硬性要求） ----
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.trash2,
                label: l10n.deleteAccount,
                destructive: true,
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
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
      if (context.mounted) await ref.read(authProvider.notifier).logout();
    } catch (e) {
      if (context.mounted) showAppToast(context, '$e', destructive: true);
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.logoutConfirm,
      body: l10n.logoutConfirm,
      confirmLabel: l10n.logout,
      destructive: true,
    );
    if (confirmed && context.mounted) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showCortermSheetDialog<bool>(
      context: context,
      title: l10n.changePassword,
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
    );
    if (ok != true) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
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
