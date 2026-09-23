import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/models/auth_models.dart';
import '../../../app/theme/app_theme.dart';
import '../../legal/legal_screens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/brand_logos.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';

/// 登录页：密码 + 手机号（由 /api/auth/methods 决定显示）。
/// 403 CAPTCHA_REQUIRED → 弹滑块验证码（拖到位松手即校验）后自动重试。
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

  final _userFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();

  bool _passwordMode = true;
  bool _obscure = true;
  bool _consented = false;
  bool _busy = false;
  bool _methodsLoaded = false;
  bool _methodsFailed = false;
  String? _methodsErrorDetail;
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
        // 平台能力判断（非降级）：Apple 原生流仅 iOS 提供（web 不提供）。
        _hasApple = methods.methods.contains('apple') &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS;
        _methodsLoaded = true;
        _methodsFailed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // methods 拉取失败不阻塞登录（默认展示密码登录），但如实提示原始错误 + 重试。
        _methodsLoaded = true;
        _methodsFailed = true;
        _methodsErrorDetail = e.toString();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_user, _password, _phone, _code]) {
      c.dispose();
    }
    for (final f in [_userFocus, _passwordFocus, _phoneFocus, _codeFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  /// 国内商店合规：未勾选时点登录 → Alert「同意并继续」，不额外打断流程。
  Future<bool> _ensureConsent() async {
    if (_consented) return true;
    final l10n = AppLocalizations.of(context)!;
    final agreed = await showCortermSheetDialog<bool>(
      context: context,
      title: l10n.consentAlertTitle,
      child: Builder(
        builder: (bodyContext) => Text(
          l10n.consentAlertBody,
          style: ShadTheme.of(bodyContext)
              .textTheme
              .muted
              .copyWith(color: ShadTheme.of(bodyContext).colorScheme.mutedForeground),
        ),
      ),
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
    );
    if (agreed == true && mounted) {
      setState(() => _consented = true);
      return true;
    }
    return false;
  }

  /// 勾选行内的《文档》链接：导航到全文页（路由名显式传入，LegalDocument 无值相等语义）。
  TextSpan _docLink(BuildContext context, String label, String route) {
    final scheme = ShadTheme.of(context).colorScheme;
    return TextSpan(
      text: '《$label》',
      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          context.push('/legal/$route');
        },
    );
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _ensureConsent()) return;
    _userFocus.unfocus();
    _passwordFocus.unfocus();
    _phoneFocus.unfocus();
    _codeFocus.unfocus();
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
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(authRepositoryProvider);
    final challenge = await repo.captchaChallenge();
    if (!mounted) throw StateError('no context for captcha');
    final token = await showCortermSheetDialog<String>(
      context: context,
      title: l10n.captchaTitle,
      child: _CaptchaDialog(
        initialChallenge: challenge,
        onVerify: (c, x) => repo.captchaVerify(id: c.id, x: x),
        onNewChallenge: () => repo.captchaChallenge(),
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
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

  /// 切换 primary 登录方式（密码 ⇄ 手机）：主表单与次行入口位置互换。
  void _switchPrimary() {
    HapticFeedback.selectionClick();
    setState(() {
      _passwordMode = !_passwordMode;
      _error = null;
    });
  }

  /// 输入即重建：登录按钮的 enabled 依赖 [_inputValid]，
  /// 只清错误不清状态会导致「打了字按钮永远不亮」。
  void _onInputChanged(String v) {
    _clearError(v);
    setState(() {});
  }

  bool get _inputValid {
    if (_passwordMode) {
      return _user.text.trim().isNotEmpty && _password.text.isNotEmpty;
    }
    return _phone.text.trim().isNotEmpty && _code.text.trim().isNotEmpty;
  }

  String? _required(String v) => v.trim().isEmpty ? ' ' : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final theme = ShadTheme.of(context);
    final localeTag = ref.watch(localeProvider);
    final privacyDoc = privacyPolicyOf(localeTag);
    final termsDoc = termsOfServiceOf(localeTag);

    // 次行入口：非 primary 的登录方式 + OAuth，横排一行。
    // 默认密码为 primary → 次行 = 手机登录 + GitHub/Google(/Apple)；
    // 切换成手机为主后，次行 = 密码登录 + OAuth。
    final secondaryEntries = <Widget>[
      if (!_passwordMode && _hasPassword)
        ShadButton.outline(
          enabled: !_busy,
          onPressed: _switchPrimary,
          leading: const Icon(LucideIcons.keyRound, size: 16),
          child: Text(l10n.passwordLogin),
        ),
      if (_passwordMode && _hasPhone)
        ShadButton.outline(
          enabled: !_busy,
          onPressed: _switchPrimary,
          leading: const Icon(LucideIcons.smartphone, size: 16),
          child: Text(l10n.phoneLogin),
        ),
      for (final p in _oauthProviders)
        ShadButton.outline(
          enabled: !_busy,
          onPressed: () => _startOauth(p),
          leading: p == 'github' ? const GithubMark() : const GoogleG(),
          child: Text(p == 'github' ? 'GitHub' : 'Google'),
        ),
      if (_hasApple)
        ShadButton.outline(
          enabled: !_busy,
          onPressed: _appleLogin,
          leading: const Icon(LucideIcons.apple, size: 16),
          child: const Text('Apple'),
        ),
    ];

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
                  const SizedBox(height: 32),
                  // 品牌区：logo + 名称 + tagline。
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/branding/icon.png',
                        width: 72,
                        height: 72,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.h2.copyWith(color: scheme.foreground),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.aboutTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.muted.copyWith(color: scheme.mutedForeground),
                  ),
                  const SizedBox(height: 32),
                  if (_passwordMode) ...[
                    ShadInputFormField(
                      controller: _user,
                      focusNode: _userFocus,
                      label: Text(l10n.username),
                      placeholder: Text(l10n.username),
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      enabled: !_busy,
                      validator: _required,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: _onInputChanged,
                    ),
                    const SizedBox(height: 16),
                    ShadInputFormField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      label: Text(l10n.password),
                      placeholder: Text(l10n.password),
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                      enabled: !_busy,
                      validator: _required,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: _onInputChanged,
                      trailing: _EyeButton(
                        obscure: _obscure,
                        onToggle: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ] else ...[
                    ShadInputFormField(
                      controller: _phone,
                      focusNode: _phoneFocus,
                      label: Text(l10n.phoneNumber),
                      placeholder: Text(l10n.phoneNumber),
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _codeFocus.requestFocus(),
                      enabled: !_busy,
                      validator: _required,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: _onInputChanged,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: ShadInputFormField(
                            controller: _code,
                            focusNode: _codeFocus,
                            label: Text(l10n.verificationCode),
                            placeholder: Text(l10n.verificationCode),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                            enabled: !_busy,
                            validator: _required,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            onChanged: _onInputChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 高度与输入框对齐（sm = 40）。
                        ShadButton(
                          size: ShadButtonSize.sm,
                          enabled: _resendIn <= 0 && _phone.text.trim().isNotEmpty && !_busy,
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
                  // 登录失败（服务器/网络）——独立于 methods 加载失败。
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ShadAlert.destructive(
                      icon: const Icon(LucideIcons.circleAlert),
                      title: Text(l10n.loginFailed),
                      description: Text(_error!),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ShadButton(
                    size: ShadButtonSize.lg,
                    enabled: !_busy && _methodsLoaded && _inputValid,
                    onPressed: _login,
                    leading: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: ShadProgress(value: null),
                          )
                        : null,
                    child: Text(_busy ? l10n.signingIn : l10n.signIn),
                  ),
                  if (secondaryEntries.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            l10n.otherLoginMethods,
                            style: theme.textTheme.muted.copyWith(
                              color: scheme.mutedForeground,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 次行入口：非 primary 的登录方式 + OAuth。
                    // Wrap 而非 Row+Expanded：条目多/文案长时按钮保持自然宽度并换行，
                    // 不会被压缩到内部 Row 溢出（等宽压缩正是 overflow 的来源）。
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final entry in secondaryEntries) entry],
                    ),
                  ],
                  if (_methodsFailed) ...[
                    const SizedBox(height: 8),
                    ShadAlert(
                      icon: const Icon(LucideIcons.wifiOff),
                      title: Text(l10n.loginMethodsUnavailable),
                      description: Text(_methodsErrorDetail ?? ''),
                    ),
                    Center(
                      child: ShadButton.link(
                        onPressed: _loadMethods,
                        child: Text(l10n.retry),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // 国内商店合规勾选行：页面最底部；整行可点；
                  // 未勾选直接点登录 → 弹「同意并继续」对话框（见 _ensureConsent）。
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _consented = !_consented),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 20,
                            child: ShadCheckbox(
                              value: _consented,
                              onChanged: (v) => setState(() => _consented = v),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text.rich(
                                TextSpan(
                                  style: theme.textTheme.muted
                                      .copyWith(color: scheme.mutedForeground),
                                  children: [
                                    TextSpan(text: l10n.consentPrefix),
                                    _docLink(context, termsDoc.title, 'terms'),
                                    TextSpan(text: l10n.consentAnd),
                                    _docLink(context, privacyDoc.title, 'privacy'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// 密码可见性切换（紧凑 28×28，不撑高输入框）。
class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.obscure, required this.onToggle});

  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onToggle,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          obscure ? LucideIcons.eye : LucideIcons.eyeOff,
          size: 16,
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

/// 滑块验证码（居中 Dialog）：
/// 拖动滑块带动拼图块，**松手即校验**——成功（绿 ✓）500ms 后自动关闭返回 token；
/// 失败：抖动 + 滑块回位 + 自动换题。坐标校验空间为 300px 原图（显示按宽度缩放）。
class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog({
    required this.initialChallenge,
    required this.onVerify,
    required this.onNewChallenge,
  });

  final CaptchaChallenge initialChallenge;
  final Future<String> Function(CaptchaChallenge c, double naturalX) onVerify;
  final Future<CaptchaChallenge> Function() onNewChallenge;

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

enum _CaptchaPhase { idle, verifying, success, failed }

class _CaptchaImages {
  _CaptchaImages({required this.background, required this.slider});

  final ui.Image background;
  final ui.Image slider;
}

class _CaptchaDialogState extends State<_CaptchaDialog>
    with SingleTickerProviderStateMixin {
  late CaptchaChallenge _challenge;
  double _dx = 0; // 显示像素位移
  double _scale = 1; // 显示宽 / 原始宽（build 时更新）
  double _maxDx = 1;
  _CaptchaPhase _phase = _CaptchaPhase.idle;
  String? _error;
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late Future<_CaptchaImages> _images = _loadImages(_challenge);

  @override
  void initState() {
    super.initState();
    _challenge = widget.initialChallenge;
    // 失败抖动：左右衰减位移序列。
    _shake.addListener(() => setState(() {}));
  }

  Future<_CaptchaImages> _loadImages(CaptchaChallenge c) async {
    final bg = await _decode(c.backgroundImage);
    final slider = await _decode(c.sliderImage);
    return _CaptchaImages(background: bg, slider: slider);
  }

  Future<ui.Image> _decode(String data) async {
    final raw = data.startsWith('data:') ? data.split(',').last : data;
    final bytes = base64Decode(raw);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Uint8List _bytesOf(String data) {
    final raw = data.startsWith('data:') ? data.split(',').last : data;
    return base64Decode(raw);
  }

  double get _shakeDx {
    final t = _shake.value; // 0..1
    if (t == 0 || t == 1) return 0;
    final wave = (t * 3 * 3.14159265).abs();
    return -_shake.value * 10 * (wave % 2 < 1 ? 1 : -1) * (1 - t);
  }

  Future<void> _onDragEnd(DragEndDetails _) async {
    if (_phase != _CaptchaPhase.idle) return;
    if (_dx <= 4) {
      setState(() => _dx = 0); // 位移过小视为误触，回位不校验。
      return;
    }
    await _verify();
  }

  Future<void> _verify() async {
    setState(() => _phase = _CaptchaPhase.verifying);
    try {
      // 显示位移 → 原始像素位移（Gateway 校验空间为原图坐标）。
      final token = await widget.onVerify(_challenge, _dx / _scale);
      if (!mounted) return;
      setState(() => _phase = _CaptchaPhase.success);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.of(context).pop(token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _CaptchaPhase.failed;
        _error = e.toString();
      });
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      // 自动换题：拉新挑战、滑块回位、重载图。
      final next = await widget.onNewChallenge();
      if (!mounted) return;
      setState(() {
        _challenge = next;
        _dx = 0;
        _phase = _CaptchaPhase.idle;
        _images = _loadImages(next);
      });
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    final fillColor = switch (_phase) {
      _CaptchaPhase.idle => scheme.secondary,
      _CaptchaPhase.verifying => scheme.primary.withValues(alpha: 0.25),
      _CaptchaPhase.success => scheme.success.withValues(alpha: 0.25),
      _CaptchaPhase.failed => scheme.destructive.withValues(alpha: 0.15),
    };
    final thumbColor = switch (_phase) {
      _CaptchaPhase.success => scheme.success,
      _CaptchaPhase.failed => scheme.destructive,
      _ => scheme.primary,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            FutureBuilder<_CaptchaImages>(
              future: _images,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text('${snap.error}',
                      style: theme.textTheme.muted
                          .copyWith(color: scheme.mutedForeground));
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
                      _scale = box.maxWidth / bg.width;
                      _maxDx = (box.maxWidth - slider.width * _scale)
                          .clamp(0, double.infinity);
                      return Transform.translate(
                        offset: Offset(_shakeDx, 0),
                        child: Stack(
                          children: [
                            Image.memory(
                              _bytesOf(_challenge.backgroundImage),
                              fit: BoxFit.fill,
                              width: box.maxWidth,
                            ),
                            Positioned(
                              left: _dx,
                              top: _challenge.y * _scale,
                              child: RawImage(
                                image: slider,
                                width: slider.width * _scale,
                                height: slider.height * _scale,
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
            // 拖轨：thumb 跟手，松手即校验。
            LayoutBuilder(
              builder: (context, box) {
                const thumbSize = 44.0;
                final travel = (box.maxWidth - thumbSize).clamp(0.0, double.infinity);
                final fraction = _maxDx <= 0 ? 0.0 : (_dx / _maxDx).clamp(0.0, 1.0);
                final thumbLeft = fraction * travel;
                return GestureDetector(
                  onHorizontalDragUpdate: _phase == _CaptchaPhase.idle
                      ? (d) => setState(() {
                            _dx = (_dx + d.delta.dx).clamp(0, _maxDx);
                          })
                      : null,
                  onHorizontalDragEnd: _phase == _CaptchaPhase.idle ? _onDragEnd : null,
                  child: Container(
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: scheme.muted,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // 填充条
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: thumbLeft + thumbSize,
                          child: Container(
                            decoration: BoxDecoration(
                              color: fillColor,
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                        ),
                        // 居中提示文字（拖动后淡出）
                        if (fraction < 0.15 && _phase == _CaptchaPhase.idle)
                          Center(
                            child: Text(
                              l10n.slideToVerify,
                              style: theme.textTheme.muted
                                  .copyWith(color: scheme.mutedForeground),
                            ),
                          ),
                        // Thumb
                        Positioned(
                          left: thumbLeft,
                          top: 0,
                          child: Container(
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              color: scheme.card,
                              shape: BoxShape.circle,
                              border: Border.all(color: thumbColor, width: 1.5),
                            ),
                            child: switch (_phase) {
                              _CaptchaPhase.success => Icon(LucideIcons.check,
                                  size: 20, color: scheme.success),
                              _CaptchaPhase.failed => Icon(LucideIcons.x,
                                  size: 20, color: scheme.destructive),
                              _CaptchaPhase.verifying => const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: ShadProgress(value: null),
                                ),
                              _CaptchaPhase.idle => Icon(LucideIcons.arrowRight,
                                  size: 20, color: thumbColor),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_error != null && _phase == _CaptchaPhase.failed) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.muted.copyWith(color: scheme.destructive),
              ),
            ],
          ],
    );
  }
}
