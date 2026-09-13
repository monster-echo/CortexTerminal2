import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/legal/legal_documents.dart';
import '../../legal/legal_screens.dart';
import '../../../core/models/auth_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';

/// 登录页：密码 + 手机号（由 /api/auth/methods 决定显示）。
/// 403 CAPTCHA_REQUIRED → 弹滑块验证码后自动重试（Gateway 防爆破约定）。
/// github/google 走系统浏览器 + corterm.mobile://auth 深链回跳；
/// Apple 走原生 ASAuthorization（authorizationCode → /api/auth/apple/native 换 JWT）。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _passwordMode = true;
  bool _consented = false;
  bool _busy = false;
  bool _methodsLoaded = false;
  String? _error;
  int _resendIn = 0;

  bool _hasPassword = true;
  bool _hasPhone = false;
  bool _hasApple = false;
  final List<String> _oauthProviders = [];

  /// 浏览器深链 OAuth 支持的 provider；Apple 是原生流，单独用 [_hasApple]。
  static const _supportedOauth = ['github', 'google'];

  @override
  void initState() {
    super.initState();
    _loadMethods();
    _watchOauthError();
  }

  Future<void> _loadMethods() async {
    try {
      final methods = await ref.read(authRepositoryProvider).methods();
      if (!mounted) return;
      setState(() {
        _hasPassword = methods.hasPassword;
        _hasPhone = methods.hasPhone;
        _passwordMode = methods.hasPassword || !methods.hasPhone;
        _oauthProviders.addAll(
          methods.methods.where((m) => _supportedOauth.contains(m)),
        );
        // 平台能力判断（非降级）：Apple 原生流仅 iOS 提供按钮。
        _hasApple = methods.methods.contains('apple') && Platform.isIOS;
        _methodsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // methods 拉取失败不阻塞登录（默认展示密码登录），但给出提示。
        _methodsLoaded = true;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_user, _password, _phone, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 国内商店合规：未勾选时点登录 → Alert「同意并继续」，不额外打断流程。
  Future<bool> _ensureConsent() async {
    if (_consented) return true;
    final l10n = AppLocalizations.of(context)!;
    final agreed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: Text(l10n.consentAlertTitle),
        description: Text(l10n.consentAlertBody),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.disagree),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.agree),
          ),
        ],
      ),
    );
    if (agreed == true && mounted) {
      setState(() => _consented = true);
      return true;
    }
    return false;
  }

  /// 勾选行内的《文档》链接：导航到全文页。
  TextSpan _docLink(BuildContext context, String label, LegalDocument doc) {
    final scheme = ShadTheme.of(context).colorScheme;
    return TextSpan(
      text: '《$label》',
      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LegalDocumentScreen(document: doc)),
          );
        },
    );
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _ensureConsent()) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final LoginResult result;
      if (_passwordMode) {
        result = await _passwordLogin();
      } else {
        result = await ref.read(authRepositoryProvider).verifyPhoneCode(
              phone: _phone.text.trim(),
              code: _code.text.trim(),
            );
      }
      await ref.read(authProvider.notifier).loggedIn(
            token: result.accessToken,
            username: result.username,
          );
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.serverMessage ?? '${l10n.loginFailed} (${e.statusCode})';
      });
    } on RateLimitedException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _resendIn = e.retryAfterSeconds;
      });
      _startResendTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<LoginResult> _passwordLogin() async {
    final repo = ref.read(authRepositoryProvider);
    try {
      return await repo.passwordLogin(
        username: _user.text.trim(),
        password: _password.text,
      );
    } on ApiException catch (e) {
      if (!e.isCaptchaRequired) rethrow;
      // 滑块验证码 → 通过后携带 captchaToken 重试一次。
      final token = await _solveCaptcha();
      return repo.passwordLogin(
        username: _user.text.trim(),
        password: _password.text,
        captchaToken: token,
      );
    }
  }

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _error = null);
    try {
      final repo = ref.read(authRepositoryProvider);
      try {
        await repo.sendPhoneCode(phone: _phone.text.trim());
      } on ApiException catch (e) {
        if (!e.isCaptchaRequired) rethrow;
        final token = await _solveCaptcha();
        await repo.sendPhoneCode(phone: _phone.text.trim(), captchaToken: token);
      }
      if (!mounted) return;
      setState(() => _resendIn = 60);
      _startResendTimer();
      showAppToast(context, l10n.codeSentTo(_phone.text.trim()));
    } on RateLimitedException catch (e) {
      if (!mounted) return;
      setState(() => _resendIn = e.retryAfterSeconds);
      _startResendTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// OAuth：系统浏览器 → 网关 → 302 回 corterm.mobile://auth?token=（main.dart 的 app_links 接住）。
  Future<void> _startOauth(String provider) async {
    if (!await _ensureConsent()) return;
    final gateway = ref.read(appConfigProvider);
    final redirect = Uri.encodeComponent('corterm.mobile://auth');
    final uri = Uri.parse('$gateway/api/auth/$provider?redirect=$redirect');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() => _error = AppLocalizations.of(context)!.oauthFailed(provider));
    }
  }

  /// Apple 原生登录：ASAuthorization 弹窗 → authorizationCode → gateway 换 JWT。
  /// 用户取消（AuthorizenException）视为静默返回，不算错误。
  Future<void> _appleLogin() async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _ensureConsent()) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.fullName],
      );
      final result = await ref
          .read(authRepositoryProvider)
          .appleLogin(authorizationCode: credential.authorizationCode);
      await ref.read(authProvider.notifier).loggedIn(
            token: result.accessToken,
            username: result.username,
          );
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.serverMessage ?? '${l10n.loginFailed} (${e.statusCode})';
      });
    } catch (e) {
      if (!mounted) return;
      // 用户取消 Apple 授权弹窗：静默返回，不算错误。
      if (e is SignInWithAppleAuthorizationException &&
          e.code == AuthorizationErrorCode.canceled) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  void _startResendTimer() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendIn = _resendIn - 1);
      return _resendIn > 0;
    });
  }

  Future<String> _solveCaptcha() async {
    final repo = ref.read(authRepositoryProvider);
    final challenge = await repo.captchaChallenge();
    if (!mounted) throw StateError('no context for captcha');
    final token = await showCortermSheet<String>(
      context: context,
      isScrollControlled: false,
      builder: (_) => _CaptchaSheet(
        challenge: challenge,
        onVerify: (x) => repo.captchaVerify(id: challenge.id, x: x),
      ),
    );
    if (token == null || token.isEmpty) {
      throw ApiException(403, serverMessage: 'CAPTCHA_REQUIRED');
    }
    return token;
  }

  void _watchOauthError() {
    ref.listenManual(oauthLastErrorProvider, (prev, next) {
      if (next != null && mounted) {
        setState(() => _error = next);
        ref.read(oauthLastErrorProvider.notifier).state = null;
      }
    });
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  bool get _inputValid {
    if (_passwordMode) {
      return _user.text.trim().isNotEmpty && _password.text.isNotEmpty;
    }
    return _phone.text.trim().isNotEmpty && _code.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final localeTag = ref.watch(localeProvider);
    final privacyDoc = privacyPolicyOf(localeTag);
    final termsDoc = termsOfServiceOf(localeTag);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Text(
                    l10n.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: scheme.foreground,
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (_hasPassword && _hasPhone)
                    ShadTabs<bool>(
                      value: _passwordMode,
                      onChanged: (v) => setState(() => _passwordMode = v),
                      tabs: [
                        ShadTab(
                          value: true,
                          child: Text(l10n.passwordLogin),
                        ),
                        ShadTab(
                          value: false,
                          child: Text(l10n.phoneLogin),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (_passwordMode) ...[
                    ShadInputFormField(
                      controller: _user,
                      label: Text(l10n.username),
                      placeholder: Text(l10n.username),
                      autofillHints: const [AutofillHints.username],
                      onChanged: _clearError,
                    ),
                    const SizedBox(height: 16),
                    ShadInputFormField(
                      controller: _password,
                      label: Text(l10n.password),
                      placeholder: Text(l10n.password),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onChanged: _clearError,
                    ),
                  ] else ...[
                    ShadInputFormField(
                      controller: _phone,
                      label: Text(l10n.phoneNumber),
                      placeholder: Text(l10n.phoneNumber),
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      onChanged: _clearError,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ShadInputFormField(
                            controller: _code,
                            label: Text(l10n.verificationCode),
                            placeholder: Text(l10n.verificationCode),
                            keyboardType: TextInputType.number,
                            onChanged: _clearError,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShadButton.outline(
                          enabled: _resendIn <= 0,
                          onPressed: _sendCode,
                          child: Text(
                            _resendIn > 0
                                ? l10n.phoneCodeResendIn(_resendIn)
                                : l10n.sendCode,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.destructive, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ShadButton(
                    enabled: !_busy && _methodsLoaded && _inputValid,
                    onPressed: _login,
                    child: Text(_busy ? l10n.signingIn : l10n.signIn),
                  ),
                  if (_oauthProviders.isNotEmpty || _hasApple) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            l10n.otherLoginMethods,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.mutedForeground,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final p in _oauthProviders)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: ShadButton.outline(
                              leading: Icon(
                                p == 'github'
                                    ? LucideIcons.code
                                    : LucideIcons.globe,
                                size: 18,
                              ),
                              enabled: !_busy,
                              onPressed: () => _startOauth(p),
                              child: Text(p == 'github' ? 'GitHub' : 'Google'),
                            ),
                          ),
                        if (_hasApple)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: ShadButton.outline(
                              leading: const Icon(LucideIcons.apple, size: 18),
                              enabled: !_busy,
                              onPressed: _appleLogin,
                              child: const Text('Apple'),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 国内商店合规勾选行：内联链接直达全文页（不阻塞提交，见 _ensureConsent）。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShadCheckbox(
                        value: _consented,
                        onChanged: (v) => setState(() => _consented = v),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.mutedForeground,
                              ),
                              children: [
                                TextSpan(text: l10n.consentPrefix),
                                _docLink(context, termsDoc.title, termsDoc),
                                TextSpan(text: l10n.consentAnd),
                                _docLink(context, privacyDoc.title, privacyDoc),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 滑块验证码：Gateway 生成 300×H 原始图，验证坐标为**原始像素位移**
/// （CaptchaService.Verify: userX vs targetX-initialPieceX），显示时按宽度缩放、提交时换算回原始 px。
class _CaptchaSheet extends StatefulWidget {
  const _CaptchaSheet({required this.challenge, required this.onVerify});

  final CaptchaChallenge challenge;
  final Future<String> Function(double naturalX) onVerify;

  @override
  State<_CaptchaSheet> createState() => _CaptchaSheetState();
}

class _CaptchaImages {
  _CaptchaImages({required this.background, required this.slider});

  final ui.Image background;
  final ui.Image slider;
}

class _CaptchaSheetState extends State<_CaptchaSheet> {
  double _dx = 0; // 显示像素位移
  double _scale = 1; // 显示宽 / 原始宽（build 时更新）
  bool _verifying = false;
  String? _error;
  late final Future<_CaptchaImages> _images = _loadImages();

  Future<_CaptchaImages> _loadImages() async {
    final bg = await _decode(widget.challenge.backgroundImage);
    final slider = await _decode(widget.challenge.sliderImage);
    return _CaptchaImages(background: bg, slider: slider);
  }

  Future<ui.Image> _decode(String data) async {
    final raw = data.startsWith('data:') ? data.split(',').last : data;
    final bytes = base64Decode(raw);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<_CaptchaImages>(
              future: _images,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text('${snap.error}', style: const TextStyle(fontSize: 13));
                }
                if (!snap.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: ShadProgress(value: null),
                      ),
                    ),
                  );
                }
                final bg = snap.data!.background;
                final slider = snap.data!.slider;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final scale = box.maxWidth / bg.width;
                      _scale = scale;
                      final maxDx = box.maxWidth - slider.width * scale;
                      return GestureDetector(
                        onHorizontalDragUpdate: _verifying
                            ? null
                            : (d) => setState(() {
                                  _dx = (_dx + d.delta.dx).clamp(0, maxDx < 0 ? 0 : maxDx);
                                }),
                        child: Stack(
                          children: [
                            Image.memory(
                              _bytesOf(widget.challenge.backgroundImage),
                              fit: BoxFit.fill,
                              width: box.maxWidth,
                            ),
                            Positioned(
                              left: _dx,
                              top: widget.challenge.y * scale,
                              child: RawImage(
                                image: slider,
                                width: slider.width * scale,
                                height: slider.height * scale,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ShadButton(
              enabled: !_verifying,
              onPressed: _submit,
              child: Text(_verifying ? l10n.verifying : l10n.slideToVerify),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShadTheme.of(context).colorScheme.destructive,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Uint8List _bytesOf(String data) {
    final raw = data.startsWith('data:') ? data.split(',').last : data;
    return base64Decode(raw);
  }

  Future<void> _submit() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      // 显示位移 → 原始像素位移（Gateway 校验空间为 300px 原图）。
      final naturalDx = _dx / _scale;
      final token = await widget.onVerify(naturalDx);
      if (mounted) Navigator.of(context).pop(token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = e.toString();
      });
    }
  }
}
