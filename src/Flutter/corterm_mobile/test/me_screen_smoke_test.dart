import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/features/membership/presentation/me_screen.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';
import 'package:corterm_mobile/features/profile/data/profile_repository.dart';
import 'package:corterm_mobile/features/membership/data/store_purchase_controller.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  AuthController fakeAuth() {
    final controller = AuthController(_FakeStore());
    controller.state = const AuthState(
      status: AuthStatus.authenticated,
      username: 'tester',
    );
    return controller;
  }

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => fakeAuth()),
        profileRepositoryProvider.overrideWith((ref) => FakeProfileRepo()),
        membershipStatusProvider.overrideWith((ref) async => {'tier': 'free'}),
      ],
      child: ShadApp(
        materialThemeBuilder: (context, theme) =>
            theme.copyWith(extensions: const [CortermColors.light]),
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
}

class _FakeStore implements TokenStore {
  @override
  String? get token => 'fake-token';
  @override
  String? get username => 'tester';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
