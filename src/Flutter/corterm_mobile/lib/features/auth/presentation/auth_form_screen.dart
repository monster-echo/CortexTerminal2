import '../../../shared/layout/adaptive_page_scaffold.dart';
import 'dart:async';
import 'dart:convert';
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
import '../../../app/theme/corterm_theme.dart';
import '../../legal/legal_screens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/brand_logos.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';

/// 登录页：密码 + 手机号（由 /api/auth/methods 决定显示）。
/// 403 CAPTCHA_REQUIRED → 弹滑块验证码（拖到位松手即校验）后自动重试。
/// github/google 走系统浏览器 + corterm.mobile://auth 深链回跳；
/// Apple 走原生 ASAuthorization（authorizationCode → /api/auth/apple/native 换 JWT）。
class AuthFormScreen extends ConsumerStatefulWidget {
  const AuthFormScreen({
    super.key,
    required this.phoneLogin,
    this.initialConsent = false,
  });

  final bool phoneLogin;
  final bool initialConsent;

  @override
  ConsumerState<AuthFormScreen> createState() => _AuthFormScreenState();
}

class _AuthFormScreenState extends ConsumerState<AuthFormScreen>
    with WidgetsBindingObserver {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  final _userFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _termsTap = TapGestureRecognizer();
  final _privacyTap = TapGestureRecognizer();

  bool get _passwordMode => !widget.phoneLogin;
  bool _sendingCode = false;
  Timer? _resendTimer;
  DateTime? _resendDeadline;
  bool _obscure = true;
  bool _consented = false;
  bool _busy = false;
  bool _methodsLoaded = false;
  bool _methodsFailed = false;
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
    _consented = widget.initialConsent;
    WidgetsBinding.instance.addObserver(this);
    _termsTap.onTap = () => context.push('/legal/terms');
    _privacyTap.onTap = () => context.push('/legal/privacy');
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
        _oauthProviders.clear();
        _oauthProviders.addAll(
          methods.methods.where((m) => _supportedOauth.contains(m)),
        );
        // 平台能力判断（非降级）：Apple 原生流仅 iOS 提供（web 不提供）。
        _hasApple =
            methods.methods.contains('apple') &&
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
    WidgetsBinding.instance.removeObserver(this);
    _resendTimer?.cancel();
    _termsTap.dispose();
    _privacyTap.dispose();
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
          style: ShadTheme.of(bodyContext).textTheme.muted
              .copyWith(color: colorsOf(bodyContext).textSecondary),
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
    final c = colorsOf(context);
    return TextSpan(
      text: Localizations.localeOf(context).languageCode == 'zh'
          ? '《$label》'
          : label,
      style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
      recognizer: route == 'terms' ? _termsTap : _privacyTap,
    );
  }

  Future<void> _login() async {
    if (_busy || _sendingCode || !_methodsLoaded || !_inputValid) return;
    final l10n = AppLocalizations.of(context)!;
    if (!await _ensureConsent() || !mounted) return;
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
        result = await ref
            .read(authRepositoryProvider)
            .verifyPhoneCode(
              phone: _phone.text.trim(),
              code: _code.text.trim(),
            );
      }
      await ref
          .read(authProvider.notifier)
          .loggedIn(token: result.accessToken, username: result.username);
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
    if (_sendingCode || _busy || _resendIn > 0 || _phone.text.trim().isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final phone = _phone.text.trim();
    setState(() {
      _error = null;
      _sendingCode = true;
    });
    try {
      if (!await _ensureConsent() || !mounted) return;
      final repo = ref.read(authRepositoryProvider);
      try {
        await repo.sendPhoneCode(phone: phone);
      } on ApiException catch (e) {
        if (!e.isCaptchaRequired) rethrow;
        final token = await _solveCaptcha();
        await repo.sendPhoneCode(phone: phone, captchaToken: token);
      }
      if (!mounted) return;
      setState(() => _resendIn = 60);
      _startResendTimer();
      showAppToast(context, l10n.codeSentTo(phone));
    } on RateLimitedException catch (e) {
      if (!mounted) return;
      setState(() {
        _resendIn = e.retryAfterSeconds;
        _error = l10n.phoneCodeResendIn(_resendIn);
      });
      _startResendTimer();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? (e.serverMessage ?? l10n.loginFailed)
              : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  /// OAuth：系统浏览器 → 网关 → 302 回 corterm.mobile://auth?token=（main.dart 的 app_links 接住）。
  Future<void> _startOauth(String provider) async {
    if (!await _ensureConsent() || !mounted) return;
    final gateway = ref.read(appConfigProvider);
    final redirect = Uri.encodeComponent('corterm.mobile://auth');
    final uri = Uri.parse('$gateway/api/auth/$provider?redirect=$redirect');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(
        () => _error = AppLocalizations.of(context)!.oauthFailed(provider),
      );
    }
  }

  /// Apple 原生登录：ASAuthorization 弹窗 → authorizationCode → gateway 换 JWT。
  /// 用户取消（AuthorizenException）视为静默返回，不算错误。
  Future<void> _appleLogin() async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _ensureConsent() || !mounted) return;
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
      await ref
          .read(authProvider.notifier)
          .loggedIn(token: result.accessToken, username: result.username);
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
    _resendTimer?.cancel();
    if (_resendIn <= 0) return;
    _resendDeadline = DateTime.now().add(Duration(seconds: _resendIn));
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) timer.cancel();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _resendDeadline == null) return;
    final remaining =
        (_resendDeadline!.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil();
    setState(() => _resendIn = remaining > 0 ? remaining : 0);
    if (_resendIn == 0) _resendTimer?.cancel();
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

  Widget _field({
    required TextEditingController controller,
    required FocusNode focus,
    required String label,
    required Iterable<String> autofillHints,
    TextInputType? keyboardType,
    bool password = false,
    bool done = false,
    VoidCallback? next,
  }) {
    final c = colorsOf(context);
    return TextField(
      controller: controller,
      focusNode: focus,
      enabled: !_busy && !_sendingCode,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      obscureText: password && _obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: done ? TextInputAction.done : TextInputAction.next,
      onSubmitted: (_) => done ? _login() : next?.call(),
      onChanged: _onInputChanged,
      style: TextStyle(fontSize: 16, color: c.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        floatingLabelStyle: TextStyle(color: c.accent, fontSize: 14),
        filled: true,
        fillColor: c.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.divider),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        suffixIcon: password
            ? _EyeButton(
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
    );
  }

  Widget _providerButton({
    required String label,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    final c = colorsOf(context);
    return IconButton.outlined(
      tooltip: label,
      onPressed: _busy ? null : onPressed,
      style: IconButton.styleFrom(
        foregroundColor: c.textPrimary,
        backgroundColor: c.surfaceElevated,
        side: BorderSide(color: c.divider),
        minimumSize: const Size(52, 52),
        padding: const EdgeInsets.all(14),
        shape: const CircleBorder(),
      ),
      icon: SizedBox(width: 22, height: 22, child: Center(child: icon)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = colorsOf(context);
    final localeTag =
        ref.watch(localeProvider) ??
        Localizations.localeOf(context).languageCode;
    final privacyDoc = privacyPolicyOf(localeTag);
    final termsDoc = termsOfServiceOf(localeTag);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String providerLabel(String name) =>
        zh ? '使用 $name 登录' : 'Continue with $name';
    final hasForm = widget.phoneLogin ? _hasPhone : _hasPassword;
    final hasAlternatives =
        !widget.phoneLogin &&
        (_oauthProviders.isNotEmpty || _hasApple || _hasPhone);

    return AdaptivePageScaffold(
      appBar: widget.phoneLogin ? AppBar(title: Text(l10n.phoneLogin)) : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 600;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(24, compact ? 16 : 28, 24, 24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.phoneLogin) ...[
                          SizedBox(height: compact ? 4 : 20),
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/branding/icon.png',
                                width: 58,
                                height: 58,
                                excludeFromSemantics: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.appName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.6,
                              color: c.textPrimary,
                            ),
                          ),
                          SizedBox(height: compact ? 28 : 42),
                        ] else ...[
                          Text(
                            l10n.phoneLoginHint,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (!_methodsLoaded) ...[
                          LinearProgressIndicator(
                            minHeight: 2,
                            color: c.accent,
                            backgroundColor: c.surface,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (hasForm) ...[
                          if (_passwordMode) ...[
                            _field(
                              controller: _user,
                              focus: _userFocus,
                              label: l10n.username,
                              autofillHints: const [AutofillHints.username],
                              next: () => _passwordFocus.requestFocus(),
                            ),
                            const SizedBox(height: 14),
                            _field(
                              controller: _password,
                              focus: _passwordFocus,
                              label: l10n.password,
                              autofillHints: const [AutofillHints.password],
                              password: true,
                              done: true,
                            ),
                          ] else ...[
                            _field(
                              controller: _phone,
                              focus: _phoneFocus,
                              label: l10n.phoneNumber,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                              keyboardType: TextInputType.phone,
                              next: () => _codeFocus.requestFocus(),
                            ),
                            const SizedBox(height: 14),
                            _field(
                              controller: _code,
                              focus: _codeFocus,
                              label: l10n.verificationCode,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              keyboardType: TextInputType.number,
                              done: true,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed:
                                    _resendIn <= 0 &&
                                        _phone.text.trim().isNotEmpty &&
                                        !_busy &&
                                        !_sendingCode
                                    ? _sendCode
                                    : null,
                                child: Text(
                                  _sendingCode
                                      ? l10n.sendingCode
                                      : _resendIn > 0
                                      ? l10n.phoneCodeResendIn(_resendIn)
                                      : l10n.sendCode,
                                ),
                              ),
                            ),
                          ],
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: ShadAlert.destructive(
                              icon: const Icon(LucideIcons.circleAlert),
                              title: Text(l10n.loginFailed),
                              description: Text(_error!),
                            ),
                          ),
                        ],
                        if (hasForm) ...[
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed:
                                !_busy &&
                                    !_sendingCode &&
                                    _methodsLoaded &&
                                    _inputValid
                                ? _login
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: c.emphasis,
                              foregroundColor: c.onEmphasis,
                              minimumSize: const Size.fromHeight(52),
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                                horizontal: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_busy) ...[
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: c.onEmphasis,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Flexible(
                                  child: Text(
                                    _busy ? l10n.signingIn : l10n.signIn,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (hasAlternatives) ...[
                          const SizedBox(height: 30),
                          Text(
                            l10n.otherLoginMethods,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 20,
                            runSpacing: 16,
                            children: [
                              if (_hasPhone)
                                _providerButton(
                                  label: l10n.phoneLogin,
                                  icon: const Icon(
                                    Icons.smartphone_rounded,
                                    size: 22,
                                  ),
                                  onPressed: () => context.push(
                                    '/login/phone',
                                    extra: _consented,
                                  ),
                                ),
                              if (_hasApple)
                                _providerButton(
                                  label: providerLabel('Apple'),
                                  icon: const Icon(Icons.apple, size: 24),
                                  onPressed: _appleLogin,
                                ),
                              for (final provider in _oauthProviders)
                                _providerButton(
                                  label: providerLabel(
                                    provider == 'github' ? 'GitHub' : 'Google',
                                  ),
                                  icon: provider == 'github'
                                      ? GithubMark(
                                          color: c.textPrimary,
                                          size: 22,
                                        )
                                      : const GoogleG(size: 22),
                                  onPressed: () => _startOauth(provider),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 26),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: Checkbox(
                                value: _consented,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(
                                        () => _consented = value ?? false,
                                      ),
                                activeColor: c.emphasis,
                                checkColor: c.onEmphasis,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 7, left: 4),
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.6,
                                      color: c.textSecondary,
                                    ),
                                    children: [
                                      TextSpan(text: l10n.consentPrefix),
                                      _docLink(
                                        context,
                                        termsDoc.title,
                                        'terms',
                                      ),
                                      TextSpan(text: l10n.consentAnd),
                                      _docLink(
                                        context,
                                        privacyDoc.title,
                                        'privacy',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_methodsFailed) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    l10n.loginMethodsUnavailable,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _loadMethods,
                                child: Text(l10n.retry),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Password visibility with an accessible touch target and spoken label.
class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.obscure, required this.onToggle});

  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: obscure ? l10n.showPassword : l10n.hidePassword,
      onPressed: onToggle,
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: colorsOf(context).textSecondary,
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
    final c = colorsOf(context);

    final fillColor = switch (_phase) {
      _CaptchaPhase.idle => c.surface,
      _CaptchaPhase.verifying => c.accent.withValues(alpha: 0.25),
      _CaptchaPhase.success => c.success.withValues(alpha: 0.25),
      _CaptchaPhase.failed => c.danger.withValues(alpha: 0.15),
    };
    final thumbColor = switch (_phase) {
      _CaptchaPhase.success => c.success,
      _CaptchaPhase.failed => c.danger,
      _ => c.accent,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<_CaptchaImages>(
          future: _images,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(
                '${snap.error}',
                style: theme.textTheme.muted.copyWith(color: c.textSecondary),
              );
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
                  _maxDx = (box.maxWidth - slider.width * _scale).clamp(
                    0,
                    double.infinity,
                  );
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
            final travel = (box.maxWidth - thumbSize).clamp(
              0.0,
              double.infinity,
            );
            final fraction = _maxDx <= 0 ? 0.0 : (_dx / _maxDx).clamp(0.0, 1.0);
            final thumbLeft = fraction * travel;
            return GestureDetector(
              onHorizontalDragUpdate: _phase == _CaptchaPhase.idle
                  ? (d) => setState(() {
                      _dx = (_dx + d.delta.dx).clamp(0, _maxDx);
                    })
                  : null,
              onHorizontalDragEnd: _phase == _CaptchaPhase.idle
                  ? _onDragEnd
                  : null,
              child: Container(
                height: thumbSize,
                decoration: BoxDecoration(
                  color: c.surface,
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
                          style: theme.textTheme.muted.copyWith(
                            color: c.textSecondary,
                          ),
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
                          color: c.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: thumbColor, width: 1.5),
                        ),
                        child: switch (_phase) {
                          _CaptchaPhase.success => Icon(
                            LucideIcons.check,
                            size: 20,
                            color: c.success,
                          ),
                          _CaptchaPhase.failed => Icon(
                            LucideIcons.x,
                            size: 20,
                            color: c.danger,
                          ),
                          _CaptchaPhase.verifying => const SizedBox(
                            width: 18,
                            height: 18,
                            child: ShadProgress(value: null),
                          ),
                          _CaptchaPhase.idle => Icon(
                            LucideIcons.arrowRight,
                            size: 20,
                            color: thumbColor,
                          ),
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
            style: theme.textTheme.muted.copyWith(color: c.danger),
          ),
        ],
      ],
    );
  }
}
