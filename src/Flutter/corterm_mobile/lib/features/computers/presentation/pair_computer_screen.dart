import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/auth/auth_repository.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../../shared/widgets/corterm_ui.dart';

/// 新建电脑（design/02 §2）：扫码配对 + 或输入配对码。
/// 复用 activate 的 AuthRepository.verifyActivationCode 与 user code 提取正则，
/// UI 按 design/07 重建（黑底扫码页保留，成功/输入页用新 token）。
class PairComputerScreen extends ConsumerStatefulWidget {
  const PairComputerScreen({super.key});

  @override
  ConsumerState<PairComputerScreen> createState() => _PairComputerScreenState();
}

class _PairComputerScreenState extends ConsumerState<PairComputerScreen> {
  final _controller = MobileScannerController();
  final _code = TextEditingController();
  bool _manual = false;
  bool _verifying = false;
  bool _scanned = false;
  bool _confirmed = false;
  String? _error;
  String _tr(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void dispose() {
    _controller.dispose();
    _code.dispose();
    super.dispose();
  }

  /// 从扫码内容提取 user code：优先取 URL 的 `code` 查询参数，裸配对码也可以。
  String _extractUserCode(String raw) {
    final match = RegExp(r'[?&]code=([A-Za-z0-9-]+)').firstMatch(raw);
    final candidate = match?.group(1) ?? raw.trim();
    final cleaned = candidate.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    return cleaned.length == 8 ? cleaned : '';
  }

  Future<void> _verify(String code) async {
    if (_verifying || _confirmed) return;
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyActivationCode(userCode: code);
      if (!mounted) return;
      ref.invalidate(workersProvider);
      setState(() => _confirmed = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('invalid_code')
            ? _tr(
                '配对码无效或已过期，请在电脑端获取新的配对码。',
                'The pairing code is invalid or expired. Get a new code on your computer.',
              )
            : '$e';
        _verifying = false;
      });
    }
  }

  Future<void> _onScanned(String raw) async {
    final code = _extractUserCode(raw);
    if (code.isEmpty) {
      setState(
        () => _error = _tr(
          '无法识别二维码中的配对码',
          'No valid pairing code in this QR code',
        ),
      );
      return;
    }
    await _verify(code);
  }

  /// 输入自动格式化为大写字母数字 + 连字符分组。
  void _onCodeChanged(String raw) {
    final chars = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final sb = StringBuffer();
    for (var i = 0; i < chars.length && i < 8; i++) {
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
    setState(() => _error = null);
  }

  bool get _valid =>
      RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(_code.text.trim());

  @override
  Widget build(BuildContext context) {
    if (_confirmed) {
      return _SuccessPage(
        onDone: () =>
            context.canPop() ? context.pop() : context.go('/computers'),
      );
    }
    return _manual ? _buildManualEntry() : _buildScanner();
  }

  Widget _buildScanner() {
    return AdaptivePageScaffold(
      backgroundColor: colorsOf(context).scrim,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: colorsOf(context).onScrim,
        title: Text(_tr('连接电脑', 'Connect computer')),
        leading: context.canPop()
            ? BackButton(onPressed: () => context.pop())
            : CloseButton(onPressed: () => context.go('/home')),
      ),
      body: Stack(
        children: [
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
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorsOf(context).onScrim),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorsOf(context).onScrim,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _tr(
                      '扫描电脑端 Corterm 显示的二维码',
                      'Scan the QR code shown in Corterm on your computer',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorsOf(context).onScrim,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorsOf(context).danger),
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
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => setState(() => _manual = true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorsOf(context).onScrim,
                            side: BorderSide(
                              color: colorsOf(context).onScrim
                                  .withValues(alpha: 0.4),
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(24),
                              ),
                            ),
                          ),
                          child: Text(_tr('输入配对码', 'Enter pairing code')),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntry() {
    final c = colorsOf(context);
    return AdaptivePageScaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(_tr('连接电脑', 'Connect computer')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                _tr(
                  '在电脑端 Corterm 的登录页面获取配对码。配对码过期后，请在电脑端重新获取。',
                  'Get a pairing code from the Corterm sign-in screen on your computer. If it expires, request a new code there.',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _tr('配对码', 'Pairing code'),
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                autofocus: true,
                enabled: !_verifying,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (_valid) _verify(_code.text.trim());
                },
                onChanged: _onCodeChanged,
                style: TextStyle(
                  fontSize: 20,
                  color: c.textPrimary,
                  fontFamily: 'monospace',
                  letterSpacing: 3,
                ),
                decoration: InputDecoration(
                  hintText: 'XXXX-XXXX',
                  filled: true,
                  fillColor: c.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.divider),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(fontSize: 14, color: c.danger)),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: _verifying ? _tr('配对中…', 'Pairing…') : _tr('配对', 'Pair'),
                onPressed: (!_verifying && _valid)
                    ? () => _verify(_code.text.trim())
                    : null,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => setState(() => _manual = false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.divider),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                  ),
                  child: Text(_tr('扫二维码', 'Scan QR code')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 配对成功页（design/07 token）。
class _SuccessPage extends StatelessWidget {
  const _SuccessPage({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return AdaptivePageScaffold(
      backgroundColor: c.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 56, color: c.success),
                const SizedBox(height: 16),
                Text(
                  Localizations.localeOf(context).languageCode == 'zh'
                      ? '配对成功'
                      : 'Computer paired',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Localizations.localeOf(context).languageCode == 'zh'
                      ? '电脑已进入电脑列表，可以继续创建工作区。'
                      : 'Your computer is listed. You can now create a workspace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                PrimaryButton(
                  label: Localizations.localeOf(context).languageCode == 'zh'
                      ? '完成'
                      : 'Done',
                  onPressed: onDone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
