import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/app_localizations.dart';
import '../core/lifecycle/app_lifecycle.dart';
import '../core/net/connectivity_watcher.dart';
import '../core/storage/app_preferences.dart';
import '../features/sessions/data/sessions_providers.dart';
import '../features/workspace/workspace_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// App 根：ShadApp.router（shadcn 框架要求的根，内部桥接 go_router 与 l10n）。
/// ShadToaster 提供全局 toast 通道（Sonner 风格反馈统一走它）。
/// 另挂两路系统事件：前后台切换（退后台断连/回前台重连）、网络恢复重连。
class CortermApp extends ConsumerStatefulWidget {
  const CortermApp({super.key});

  @override
  ConsumerState<CortermApp> createState() => _CortermAppState();
}

class _CortermAppState extends ConsumerState<CortermApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(AppLifecycleObserver(
      onPaused: () => ref.read(workspaceControllerProvider.notifier).enterBackground(),
      onResumed: () {
        ref.read(workspaceControllerProvider.notifier).reattachAll();
        ref.invalidate(sessionsProvider);
      },
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        ref.read(workspaceControllerProvider.notifier).reattachAll();
      }
    });

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
