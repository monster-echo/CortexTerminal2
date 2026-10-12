import 'package:flutter/widgets.dart';

import 'corterm_service.dart';

/// 全局依赖下发：go_router 的 route builder 拿不到构造参数，
/// 页面统一通过 [AppScope.of] 获取 CortermService。
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.service, required super.child});

  final CortermService service;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
