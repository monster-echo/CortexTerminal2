import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// web 构建的 no-op 实现：本项目未配置 Firebase web 端，
/// 分析在 web 上不生效（与「Apple 仅 iOS」同性质的平台能力边界，非错误降级）。
class AnalyticsService {
  AnalyticsService();

  Future<void> track(String event, [Map<String, Object> parameters = const {}]) async {}

  Future<void> setUserId(String userId) async {}

  NavigatorObserver get observer => NavigatorObserver();
}

final analyticsProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});
