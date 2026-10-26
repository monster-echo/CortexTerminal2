import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:corterm_mobile/app/router.dart';
import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/core/analytics/analytics_service.dart';
import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/features/auth/presentation/phone_login_screen.dart';
import 'package:corterm_mobile/features/home/home_shell.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';

import 'fakes.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/api/api_exception.dart';
import 'package:corterm_mobile/core/auth/auth_repository.dart';
import 'package:corterm_mobile/core/models/auth_models.dart';
import 'package:corterm_mobile/features/auth/presentation/login_screen.dart';

import 'pages/test_harness.dart';

class _AnalyticsFake extends Fake implements AnalyticsService {
  @override
  NavigatorObserver get observer => NavigatorObserver();
}

class _TokenStore extends FakeTokenStore {
  @override
  Future<void> save({required String token, required String username}) async {}
}

class LoginFake extends Fake implements AuthRepository {
  bool phoneSuccess = false;
  int sends = 0;
  Completer<void>? sending;
  Object? sendError;
  @override
  Future<void> sendPhoneCode({
    required String phone,
    String? captchaToken,
  }) async {
    sends++;
    if (sendError != null) throw sendError!;
    await sending?.future;
  }

  int passwordCalls = 0;
  int phoneCalls = 0;
  String? username;
  @override
  Future<AuthMethods> methods() async =>
      const AuthMethods(methods: ['password', 'phone', 'github', 'google']);
  @override
  Future<LoginResult> passwordLogin({
    required String username,
    required String password,
    String? captchaToken,
  }) async {
    passwordCalls++;
    this.username = username;
    throw ApiException(401, serverMessage: '账号或密码错误');
  }

  @override
  Future<LoginResult> verifyPhoneCode({
    required String phone,
    required String code,
  }) async {
    phoneCalls++;
    if (phoneSuccess) {
      return const LoginResult(accessToken: 'test-token', username: 'tester');
    }
    throw ApiException(401, serverMessage: '验证码错误');
  }
}

void main() {
  setUp(initPageTestFixtures);
  Future<void> mount(WidgetTester tester, LoginFake repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await defaultOverrides(),
          authRepositoryProvider.overrideWithValue(repo),
          analyticsProvider.overrideWithValue(_AnalyticsFake()),
          authProvider.overrideWith((ref) {
            final auth = AuthController(_TokenStore());
            auth.state = const AuthState(status: AuthStatus.unauthenticated);
            return auth;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) => ShadApp.router(
            locale: const Locale('zh'),
            materialThemeBuilder: (context, theme) =>
                theme.copyWith(extensions: [CortermColors.light]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空表单键盘提交不会发起登录或弹出协议', (tester) async {
    final repo = LoginFake();
    await mount(tester, repo);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(TextField).last);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.passwordCalls, 0);
    expect(find.text('同意并继续'), findsNothing);
  });

  testWidgets('密码登录支持可见性切换并展示服务端错误', (tester) async {
    final repo = LoginFake();
    await mount(tester, repo);
    await tester.enterText(find.byType(TextField).first, ' user ');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isFalse,
    );
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(repo.passwordCalls, 1);
    expect(repo.username, 'user');
    expect(find.text('账号或密码错误'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('未登录用户可进入独立手机页并提交验证码', (tester) async {
    final repo = LoginFake();
    await mount(tester, repo);
    await tester.tap(find.byTooltip('手机登录'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).keyboardType,
      TextInputType.phone,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).autofillHints,
      contains(AutofillHints.oneTimeCode),
    );
    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(repo.phoneCalls, 1);
    expect(repo.passwordCalls, 0);
    expect(find.text('验证码错误'), findsOneWidget);
    expect(find.byType(PhoneLoginScreen), findsOneWidget);
    expect(find.byTooltip('使用 GitHub 登录'), findsNothing);
  });
  testWidgets('返回主登录页保留账号密码，手机入口保持手机图标', (tester) async {
    await mount(tester, LoginFake());
    await tester.enterText(find.byType(TextField).first, 'saved-user');
    await tester.enterText(find.byType(TextField).last, 'saved-password');
    await tester.ensureVisible(find.byTooltip('手机登录'));
    await tester.tap(find.byTooltip('手机登录'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneLoginScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'saved-user',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'saved-password',
    );
    expect(find.byTooltip('手机登录'), findsOneWidget);
  });

  testWidgets('发送验证码期间禁止重复点击，倒计时结束可重发', (tester) async {
    final repo = LoginFake()..sending = Completer<void>();
    await mount(tester, repo);
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byTooltip('手机登录'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.pump();
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    expect(repo.sends, 1);
    expect(find.text('发送中…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '发送中…'))
          .onPressed,
      isNull,
    );
    repo.sending!.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.sends, 1);
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '发送验证码'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  testWidgets('发送失败显示错误且允许重试', (tester) async {
    final repo = LoginFake()
      ..sendError = ApiException(500, serverMessage: '短信暂时无法发送');
    await mount(tester, repo);
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byTooltip('手机登录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.pump();
    await tester.tap(find.text('发送验证码'));
    await tester.pumpAndSettle();
    expect(find.text('短信暂时无法发送'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '发送验证码'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });
  testWidgets('未同意协议不发送短信', (tester) async {
    final repo = LoginFake();
    await mount(tester, repo);
    await tester.tap(find.byTooltip('手机登录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.pump();
    await tester.tap(find.text('发送验证码'));
    await tester.pumpAndSettle();
    expect(repo.sends, 0);
    expect(find.text('服务协议及隐私保护'), findsOneWidget);
    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();
    expect(repo.sends, 0);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '发送验证码'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  testWidgets('手机验证成功后进入首页并移除登录流程', (tester) async {
    final repo = LoginFake()..phoneSuccess = true;
    await mount(tester, repo);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.byTooltip('手机登录'));
    await tester.tap(find.byTooltip('手机登录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(repo.phoneCalls, 1);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(PhoneLoginScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
