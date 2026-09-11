import 'package:flutter/widgets.dart';

/// App 前后台切换转发器：paused → 退后台断连，resumed → 回前台重连。
/// inactive（控制中心下拉等瞬态）不触发，避免误断。
class AppLifecycleObserver with WidgetsBindingObserver {
  AppLifecycleObserver({required this.onPaused, required this.onResumed});

  final VoidCallback onPaused;
  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        onPaused();
      case AppLifecycleState.resumed:
        onResumed();
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}
