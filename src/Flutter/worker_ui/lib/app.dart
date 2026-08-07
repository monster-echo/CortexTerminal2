import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/settings.dart';
import 'core/tray_controller.dart';
import 'l10n/app_strings.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class WorkerUiApp extends StatelessWidget {
  const WorkerUiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) {
        final s = Settings.instance;
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: AppStrings.of(s.locale, 'appTitle'),
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: s.themeMode,
          locale: Locale(s.locale),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const HomeScreen(),
        );
      },
    );
  }
}
