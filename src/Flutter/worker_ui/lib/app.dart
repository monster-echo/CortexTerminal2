import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/app_router.dart';
import 'core/app_scope.dart';
import 'core/binary_locator.dart';
import 'core/corterm_service.dart';
import 'core/settings.dart';
import 'l10n/app_strings.dart';
import 'theme/app_theme.dart';
import 'widgets/error_banner.dart';
import 'widgets/states.dart';

/// App 入口：先解析 corterm 二进制（不阻塞主题），成功后才挂载路由。
class CortexApp extends StatefulWidget {
  const CortexApp({super.key});

  @override
  State<CortexApp> createState() => _CortexAppState();
}

class _CortexAppState extends State<CortexApp> {
  CortermService? _service;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final paths = await resolveBinaryPaths();
    if (!mounted) return;
    if (paths == null) {
      setState(() {
        _service = null;
        _error = AppStrings.of(Settings.instance.locale, 'binaryLocator.notFound');
      });
      return;
    }
    setState(() {
      _service = CortermService(cortermPath: paths.corterm, cortapPath: paths.cortap);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    // 启动解析中的极简过渡壳（毫秒级）；失败时给出可重试错误。
    if (service == null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorBanner(message: _error, onRetry: _resolve),
                  )
                : const SmallSpinner(),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Settings.instance,
      builder: (context, _) {
        final s = Settings.instance;
        return ShadApp.router(
          routerConfig: appRouter,
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
          builder: (context, child) => AppScope(
            service: service,
            child: ShadToaster(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
