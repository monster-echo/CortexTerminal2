import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corterm_mobile/core/analytics/analytics_firebase.dart'
    if (dart.library.js_interop) 'package:corterm_mobile/core/analytics/analytics_stub.dart';
import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/features/membership/presentation/me_screen.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  AuthController fakeAuth() {
    final controller = AuthController(_FakeStore());
    controller.state =
        const AuthState(status: AuthStatus.authenticated, username: 'tester');
    return controller;
  }

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [authProvider.overrideWith((ref) => fakeAuth())],
      child: ShadApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  testWidgets('MeScreen builds and shows entries', (tester) async {
    await tester.pumpWidget(wrap(const MeScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('tester'), findsOneWidget);
  });

  /// 路由回归：GoRouter 实例在应用启动时构建一次，热重载不会重建，
  /// 因此这里以纯 Dart 断言校验路由表内容（不依赖 Firebase observer）。
  test('route table contains /me and root redirect exists', () {
    final routerSource = File('lib/app/router.dart').readAsStringSync();
    expect(routerSource.contains("GoRoute(path: '/me'"), isTrue,
        reason: '/me route must be registered');
    expect(routerSource.contains("if (state.uri.path == '/')"), isTrue,
        reason: "root '/' must redirect instead of throwing GoException");
    expect(routerSource.contains('errorBuilder'), isTrue,
        reason: 'unknown paths must render error page, not throw');
  });
}

class _FakeStore implements TokenStore {
  @override
  String? get token => 'fake-token';
  @override
  String? get username => 'tester';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
