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
