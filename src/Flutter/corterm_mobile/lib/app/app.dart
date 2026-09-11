import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/app_localizations.dart';
import '../core/storage/app_preferences.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// App 根：ShadApp.router（shadcn 框架要求的根，内部桥接 go_router 与 l10n）。
/// ShadToaster 提供全局 toast 通道（Sonner 风格反馈统一走它）。
class CortermApp extends ConsumerWidget {
  const CortermApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final localeTag = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);

    return ShadApp.router(
      routerConfig: router,
      theme: shadLightTheme(),
      darkTheme: shadDarkTheme(),
      themeMode: themeMode,
      locale: (localeTag == null || localeTag.isEmpty) ? null : Locale(localeTag),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ShadToaster(child: child ?? const SizedBox.shrink()),
    );
  }
}
