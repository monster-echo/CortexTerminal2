import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Analytics 实现（原生平台）。
/// 失败原样抛出（调用方决定如何呈现）。
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
