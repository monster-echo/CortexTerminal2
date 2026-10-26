import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:corterm_mobile/app/router.dart';
import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/core/analytics/analytics_service.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';

import 'pages/test_harness.dart';

class _Analytics extends Fake implements AnalyticsService {
  @override
  NavigatorObserver get observer => NavigatorObserver();
}

void main() {
  setUp(initPageTestFixtures);
  testWidgets(
    'actual router reaches account, redirects root, and recovers unknown paths',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          ...await defaultOverrides(),
          analyticsProvider.overrideWithValue(_Analytics()),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadApp.router(
            routerConfig: router,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            materialThemeBuilder: (context, theme) =>
                theme.copyWith(extensions: [CortermColors.light]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go('/me');
      await tester.pumpAndSettle();
      expect(find.text('tester'), findsOneWidget);
      router.go('/');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      router.go('/page-that-does-not-exist');
      await tester.pumpAndSettle();
      expect(find.text('Go home'), findsOneWidget);
      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(tester.takeException(), isNull);
    },
  );
}
