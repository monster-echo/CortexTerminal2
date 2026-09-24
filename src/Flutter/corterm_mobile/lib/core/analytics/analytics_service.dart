/// 埋点门面：平台条件导入。
/// 原生走 Firebase Analytics；web 构建未配置 Firebase → no-op 实现。
/// 事件名常量在 [AnalyticsEvents]（analytics_events.dart）。
library;
export 'analytics_events.dart';
export 'analytics_firebase.dart' if (dart.library.js_interop) 'analytics_stub.dart';
