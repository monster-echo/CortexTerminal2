import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';

/// 设备激活：扫码优先。worker / 桌面端显示的二维码编码
/// `<verification_uri>?code=<user_code>`（见 worker_ui auth_screen），
/// App 扫码提取 code 参数后直接调用 device-flow/verify 授权；
/// 也保留手动输入 XXXX-XXXX 的方式（对齐 HarmonyOS ActivateWorkerPage）。
class ActivateScreen extends ConsumerStatefulWidget {
  const ActivateScreen({super.key});

  @override
  ConsumerState<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends ConsumerState<ActivateScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  bool _scanning = false;
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

  /// 从扫码内容提取 user code：优先取 URL 的 `code` 查询参数，
  /// 裸激活码也可以。与 HarmonyOS ActivateWorkerPage.extractUserCode 对齐。
  String _extractUserCode(String raw) {
    final match = RegExp(r'[?&]code=([A-Za-z0-9-]+)').firstMatch(raw);
    final candidate = match?.group(1) ?? raw.trim();
    final cleaned = candidate.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length >= 4 ? cleaned.substring(0, 8) : '';
  }

  Future<void> _onScanned(String raw) async {
    final l10n = AppLocalizations.of(context)!;
    final code = _extractUserCode(raw);
    if (code.isEmpty) {
      setState(() => _error = l10n.activateScanInvalid);
      return;
    }
    _code.text = code;
    await _verify();
  }

  /// 打开全屏扫码页。识别到二维码立即返回（条码去抖由 [_ScanScreen] 保证）。
  Future<void> _startScan() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _error = null;
      _scanning = true;
    });
    try {
      final raw = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _ScanScreen()),
      );
      if (raw == null || !mounted) return;
      await _onScanned(raw);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.activateScanFailed('$e'));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

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
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

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
                  style:
                      theme.textTheme.small.copyWith(color: scheme.mutedForeground, height: 1.5),
                ),
                const SizedBox(height: 24),
                if (_confirmed) ...[
                  Icon(LucideIcons.circleCheck, size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.activateDone,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.small.copyWith(
                        fontWeight: FontWeight.w600, color: scheme.foreground),
                  ),
                ] else ...[
                  // 主操作：扫码授权
                  ShadButton(
                    enabled: !_scanning && !_verifying,
                    onPressed: _startScan,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_scanning)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Icon(LucideIcons.scanLine, size: 18),
                        const SizedBox(width: 8),
                        Text(_scanning ? l10n.verifying : l10n.activateScan),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: theme.textTheme.small.copyWith(color: scheme.destructive)),
                  ],
                  const SizedBox(height: 32),
                  // 次要方式：手动输入激活码
                  Text(
                    l10n.activateManualEntry,
                    style: theme.textTheme.small.copyWith(
                        fontWeight: FontWeight.w600, color: scheme.foreground),
                  ),
                  const SizedBox(height: 12),
                  ShadInputFormField(
                    controller: _code,
                    label: Text(l10n.activateCodeLabel),
                    placeholder: const Text('XXXX-XXXX'),
                    onChanged: _onCodeChanged,
                    style: theme.textTheme.large
                        .copyWith(fontFamily: 'monospace', letterSpacing: 3),
                  ),
                  const SizedBox(height: 24),
                  ShadButton.secondary(
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

/// 全屏扫码页：识别到激活二维码后 pop 返回原始内容。
/// 相机权限由 mobile_scanner 内部申请，失败/被拒时异常上抛由调用方展示。
class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.activateScan),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
