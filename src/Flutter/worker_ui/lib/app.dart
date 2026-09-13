import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
        return ShadApp(
          navigatorKey: appNavigatorKey,
          title: AppStrings.of(s.locale, 'appTitle'),
          theme: shadLightTheme(),
          darkTheme: shadDarkTheme(),
          themeMode: s.themeMode,
          locale: Locale(s.locale),
          supportedLocales: const [Locale('zh'), Locale('en')],
          // 保留 Material delegates：Scaffold/AppBar 等结构件仍来自 Material
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => ShadToaster(child: child ?? const SizedBox.shrink()),
          home: const HomeScreen(),
        );
      },
    );
  }
}
