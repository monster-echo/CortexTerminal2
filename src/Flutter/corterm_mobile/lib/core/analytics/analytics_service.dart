import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 埋点事件名（对齐 MAUI globalTracker 的事件命名）。
abstract final class AnalyticsEvents {
  static const pageView = 'page_view';
  static const uiTap = 'ui_tap';
  static const appStart = 'app_start';
  static const sessionCreated = 'session_created';
  static const terminalLatency = 'terminal_latency';
  static const themeChange = 'theme_change';
  static const languageChange = 'language_change';
  static const loginSuccess = 'login_success';
  static const feedbackSubmitted = 'feedback_submitted';
}

/// 埋点门面：统一走 Firebase Analytics。失败原样抛出（调用方决定如何呈现）。
class AnalyticsService {
  AnalyticsService(this._firebase);

  final FirebaseAnalytics _firebase;

  Future<void> track(String event, [Map<String, Object> parameters = const {}]) {
    return _firebase.logEvent(name: event, parameters: parameters);
  }

  Future<void> setUserId(String userId) => _firebase.setUserId(id: userId);

  /// go_router 挂载后自动上报 page_view（screen_class = 路由路径模板）。
  NavigatorObserver get observer => FirebaseAnalyticsObserver(analytics: _firebase);
}

final analyticsProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(FirebaseAnalytics.instance);
});
