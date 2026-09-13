import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';

/// 设备流激活码（对齐 MAUI ActivatePage）：worker/cLI 设备出示 XXXX-XXXXX，
/// 已登录用户在此确认授权。
class ActivateScreen extends ConsumerStatefulWidget {
  const ActivateScreen({super.key});

  @override
  ConsumerState<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends ConsumerState<ActivateScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  String? _error;
  bool _confirmed = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// 输入自动格式化为大写字母数字 + 连字符分组（对齐 MAUI）。
  void _onCodeChanged(String raw) {
    final chars = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final sb = StringBuffer();
    for (var i = 0; i < chars.length && i < 9; i++) {
      if (i == 4) sb.write('-');
      sb.writeCharCode(chars.codeUnitAt(i));
    }
    final formatted = sb.toString();
    if (formatted != raw) {
      _code.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    if (_error != null) setState(() => _error = null);
  }

  bool get _valid => RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4,5}$').hasMatch(_code.text.trim());

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyActivationCode(userCode: _code.text.trim());
      if (!mounted) return;
      setState(() {
        _confirmed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().contains('invalid_code')
          ? l10n.activateInvalidCode
          : '$e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        title: l10n.activateTitle,
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Text(
                  l10n.activateIntro,
                  style: TextStyle(fontSize: 14, color: scheme.mutedForeground, height: 1.5),
                ),
                const SizedBox(height: 24),
                if (_confirmed) ...[
                  Icon(LucideIcons.circleCheck, size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.activateDone,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: scheme.foreground),
                  ),
                ] else ...[
                  ShadInputFormField(
                    controller: _code,
                    label: Text(l10n.activateCodeLabel),
                    placeholder: const Text('XXXX-XXXX'),
                    onChanged: _onCodeChanged,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 18, letterSpacing: 3),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: scheme.destructive, fontSize: 14)),
                  ],
                  const SizedBox(height: 24),
                  ShadButton(
                    enabled: !_verifying && _valid,
                    onPressed: _verify,
                    child: Text(_verifying ? l10n.verifying : l10n.activateConfirm),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
