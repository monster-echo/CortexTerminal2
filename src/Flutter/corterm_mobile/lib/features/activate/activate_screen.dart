import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../app/theme/corterm_theme.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/corterm_ui.dart';

/// 设备激活：一进来就是全屏扫码。worker / 桌面端显示的二维码编码
/// `<verification_uri>?code=<user_code>`（见 worker_ui auth_screen），
/// 扫码提取 code 参数后直接调用 device-flow/verify 授权；
/// 点击「手动输入激活码」进入激活码输入页（对齐 HarmonyOS EnterActivationCodePage）。
class ActivateScreen extends ConsumerStatefulWidget {
  const ActivateScreen({super.key});

  @override
  ConsumerState<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends ConsumerState<ActivateScreen> {
  final _controller = MobileScannerController();
  bool _verifying = false;
  bool _scanned = false;
  String? _error;
  bool _confirmed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 从扫码内容提取 user code：优先取 URL 的 `code` 查询参数，
  /// 裸激活码也可以。与 HarmonyOS ActivateWorkerPage.extractUserCode 对齐。
  String _extractUserCode(String raw) {
    final match = RegExp(r'[?&]code=([A-Za-z0-9-]+)').firstMatch(raw);
    final candidate = match?.group(1) ?? raw.trim();
    final cleaned = candidate.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    return cleaned.length >= 4 ? cleaned.substring(0, 8) : '';
  }

  Future<void> _onScanned(String raw) async {
    final l10n = AppLocalizations.of(context)!;
    final code = _extractUserCode(raw);
    if (code.isEmpty) {
      setState(() => _error = l10n.activateScanInvalid);
      return;
    }
    await _verify(code);
  }

  Future<void> _verify(String code) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyActivationCode(userCode: code);
      if (!mounted) return;
      setState(() {
        _confirmed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.toString().contains('invalid_code')
            ? l10n.activateInvalidCode
            : '$e',
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// 打开手动输入激活码页。返回 true 表示已在该页激活成功。
  Future<void> _openCodeEntry() async {
    final navigator = Navigator.of(context);
    await _controller.stop();
    final confirmed = await navigator.push<bool>(
      MaterialPageRoute(builder: (_) => const _CodeEntryScreen()),
    );
    if (!mounted) return;
    if (confirmed == true) {
      setState(() => _confirmed = true);
      return;
    }
    if (!mounted) return;
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);

    return Scaffold(
      backgroundColor: colorsOf(context).scrim,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: colorsOf(context).onScrim,
        title: Text(l10n.activateTitle),
        // 可能被 go 直接替换进入（无栈可弹），此时回首页兜底。
        leading: context.canPop()
            ? BackButton(onPressed: () => context.pop())
            : CloseButton(onPressed: () => context.go('/home')),
      ),
      body: Stack(
        children: [
          if (_confirmed)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.circleCheck,
                    size: 56,
                    color: c.accent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.activateDone,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorsOf(context).onScrim,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_scanned || _verifying) return;
                for (final barcode in capture.barcodes) {
                  final raw = barcode.rawValue;
                  if (raw != null && raw.isNotEmpty) {
                    _scanned = true;
                    _onScanned(raw).whenComplete(() => _scanned = false);
                    return;
                  }
                }
              },
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorsOf(context).onScrim),
                    ),
                  ),
                );
              },
            ),
            // 取景框 + 提示 + 底部手动入口
            SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.accent, width: 2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.activateScanHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.small.copyWith(
                      color: colorsOf(context).onScrim,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.small.copyWith(
                          color: c.danger,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_verifying)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: ShadButton.outline(
                        width: double.infinity,
                        height: 48,
                        foregroundColor: colorsOf(context).onScrim,
                        backgroundColor: colorsOf(context).onScrim.withValues(alpha: 0.12),
                        onPressed: _openCodeEntry,
                        child: Text(l10n.activateManualEntry),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 手动输入激活码页：输入 XXXX-XXXX 后调用 device-flow/verify 授权。
/// 激活成功 pop(true)，由扫码页展示成功态。
class _CodeEntryScreen extends ConsumerStatefulWidget {
  const _CodeEntryScreen();

  @override
  ConsumerState<_CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends ConsumerState<_CodeEntryScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  String? _error;

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

  bool get _valid =>
      RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4,5}$').hasMatch(_code.text.trim());

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
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('invalid_code')
            ? l10n.activateInvalidCode
            : '$e';
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: CortermAppBar(title: l10n.activateCodeNavTitle),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                l10n.activateIntro,
                style: theme.textTheme.small.copyWith(
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ShadInputFormField(
                controller: _code,
                label: Text(l10n.activateCodeLabel),
                placeholder: const Text('XXXX-XXXX'),
                onChanged: _onCodeChanged,
                style: theme.textTheme.large.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 3,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.small.copyWith(
                    color: c.danger,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: _verifying ? l10n.verifying : l10n.activateConfirm,
                onPressed: !_verifying && _valid ? _verify : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
