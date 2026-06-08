/**
 * AnalyticsService — HUAWEI Analytics Kit wrapper
 *
 * Tracks app events, screen views, and user properties.
 * Requires @hms.analytics.hianalytics SDK in dependencies.
 */
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'AnalyticsService'
const DOMAIN = 0x0002

/** Common analytics events the app sends. */
export enum AnalyticsEvent {
  APP_FIRST_LAUNCH = 'app_first_launch',
  USER_LOGIN = 'user_login',
  USER_LOGOUT = 'user_logout',
  SESSION_CREATE = 'session_create',
  SESSION_RESUME = 'session_resume',
  SESSION_DELETE = 'session_delete',
  WORKER_ACTIVATE = 'worker_activate',
  WORKER_UPGRADE = 'worker_upgrade',
  SCREEN_VIEW = 'screen_view',
  PASSWORD_CHANGE = 'password_change',
  ACCOUNT_DELETE = 'account_delete',
  THEME_CHANGE = 'theme_change',
  LANGUAGE_CHANGE = 'language_change',
}

export class AnalyticsService {
  private static enabled: boolean = false

  /**
   * Initialize the Analytics Kit SDK. Must be called once in EntryAbility.onCreate().
   * When the HMS Analytics SDK is installed, uncomment the native init code.
   */
  static init(): void {
    AnalyticsService.enabled = true
    hilog.info(DOMAIN, TAG, 'AnalyticsService initialized')
  }

  /**
   * Report a custom event without params.
   */
  static onEvent(event: AnalyticsEvent): void {
    if (!AnalyticsService.enabled) {
      return
    }
    hilog.info(DOMAIN, TAG, `Event: ${event}`)
  }

  /**
   * Track a screen view.
   */
  static onPageStart(pageName: string): void {
    hilog.info(DOMAIN, TAG, `Page: ${pageName}`)
  }

  /**
   * Set user identifier. Call after login.
   */
  static setUserId(userId: string): void {
    if (!AnalyticsService.enabled) {
      return
    }
    hilog.info(DOMAIN, TAG, `UserId: ${userId}`)
  }
}
