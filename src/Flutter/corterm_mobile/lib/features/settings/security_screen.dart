import '../../shared/layout/adaptive_page_scaffold.dart';

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

/// 账户与安全：修改密码、注销协议及账号注销。
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _deleting = false;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AdaptivePageScaffold(
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
                icon: LucideIcons.fileText,
                label: Localizations.localeOf(context).languageCode == 'zh'
                    ? '账户注销协议'
                    : 'Account deletion policy',
                chevron: true,
                onTap: () => context.push('/legal/deletion'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_deleting) const LinearProgressIndicator(),
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.trash2,
                label: l10n.deleteAccount,
                destructive: true,
                onTap: _deleting ? null : () => _deleteAccount(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 注销账号（App Store 硬性要求）：强确认 → DELETE /api/me/account → 清凭据回登录页。
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showConfirmDialog(
        context: context,
        title: l10n.deleteAccountConfirmTitle,
        body: l10n.deleteAccountConfirmBody,
        confirmLabel: l10n.delete,
        destructive: true,
      );
      if (!confirmed) return;
      await ref.read(authRepositoryProvider).deleteAccount();
      if (context.mounted) await ref.read(authProvider.notifier).logout();
    } catch (error) {
      if (context.mounted) showAppToast(context, '$error', destructive: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final changed = await showCortermSheet<bool>(
      context: context,
      builder: (_) => _PasswordForm(
        submit: (current, next) => ref
            .read(authRepositoryProvider)
            .changePassword(currentPassword: current, newPassword: next),
      ),
    );
    if (changed == true && context.mounted) {
      showAppToast(context, l10n.passwordChanged);
    }
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.submit});
  final Future<void> Function(String, String) submit;
  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (_current.text.isEmpty || _next.text.isEmpty) {
      setState(
        () => _error = zh
            ? '请输入当前密码和新密码。'
            : 'Enter your current and new passwords.',
      );
      return;
    }
    if (_next.text != _confirm.text) {
      setState(
        () => _error = zh ? '两次输入的新密码不一致。' : 'The new passwords do not match.',
      );
      return;
    }
    if (_current.text == _next.text) {
      setState(
        () => _error = zh ? '新密码应与当前密码不同。' : 'Choose a different new password.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(_current.text, _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.changePassword,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _current,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: l10n.currentPassword),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(labelText: l10n.newPassword),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: zh ? '确认新密码' : 'Confirm new password',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? (zh ? '保存中…' : 'Saving…') : l10n.save),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
