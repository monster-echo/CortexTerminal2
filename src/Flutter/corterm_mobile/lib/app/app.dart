import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/app_localizations.dart';
import '../features/membership/data/store_purchase_controller.dart';
import '../core/lifecycle/app_lifecycle.dart';
import '../core/net/connectivity_watcher.dart';
import '../core/storage/app_preferences.dart';
import '../features/sessions/data/sessions_providers.dart';
import '../features/session/session_controller.dart';
import 'theme/corterm_theme.dart';
import 'router.dart';
import 'theme/app_theme.dart' show shadDarkTheme, shadLightTheme;

/// App 根：ShadApp.router（shadcn 框架要求的根，内部桥接 go_router 与 l10n）。
/// ShadToaster 提供全局 toast 通道（Sonner 风格反馈统一走它）。
/// 另挂两路系统事件：前后台切换（退后台断连/回前台重连）、网络恢复重连。
class CortermApp extends ConsumerStatefulWidget {
  const CortermApp({super.key});

  @override
  ConsumerState<CortermApp> createState() => _CortermAppState();
}

class _CortermAppState extends ConsumerState<CortermApp>
    with WidgetsBindingObserver {
  late final AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = AppLifecycleObserver(
      onPaused: () =>
          ref.read(sessionControllerProvider.notifier).enterBackground(),
      onResumed: () {
        ref.read(sessionControllerProvider.notifier).reattachAll();
        ref.invalidate(sessionsProvider);
        ref.invalidate(membershipStatusProvider);
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(storePurchaseProvider);
    final themeMode = ref.watch(themeModeProvider);
    final localeTag = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);

    // 网络恢复（offline → online 跳变）→ 与回前台同一条重连路径。
    ref.listen(connectivityProvider, (prev, next) {
      final nextResults = next.value;
      if (nextResults == null) return;
      final prevResults = prev?.value;
      final wasOnline = prevResults == null || isOnline(prevResults);
      if (!wasOnline && isOnline(nextResults)) {
        ref.read(sessionControllerProvider.notifier).reattachAll();
      }
    });

    return ShadApp.router(
      routerConfig: router,
      // 应用按偏好切换深浅主题；终端单独从所选配色派生页面 tokens。
      theme: shadLightTheme(),
      darkTheme: shadDarkTheme(),
      themeMode: themeMode,
      materialThemeBuilder: (context, theme) => theme.copyWith(
        scaffoldBackgroundColor: theme.brightness == Brightness.dark
            ? CortermColors.dark.background
            : CortermColors.light.background,
        pageTransitionsTheme: cortermPageTransitions,
        bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
        appBarTheme: theme.appBarTheme.copyWith(
          centerTitle: false,
          toolbarHeight: 52,
          titleTextStyle: theme.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        extensions: [
          theme.brightness == Brightness.dark
              ? CortermColors.dark
              : CortermColors.light,
        ],
      ),
      locale: (localeTag == null || localeTag.isEmpty)
          ? null
          : Locale(localeTag),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final palette = dark ? CortermColors.dark : CortermColors.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: palette.background,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: palette.background,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: ShadToaster(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
