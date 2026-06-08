/**
 * CrashService — HUAWEI Crash Kit / fault logging wrapper
 *
 * Captures JS crashes and unhandled exceptions.
 * Reports to AppGallery Connect when app is distributed through AppGallery.
 * Uses HarmonyOS built-in APIs — no extra SDK dependency required.
 */
import { hilog } from '@kit.PerformanceAnalysisKit'
import { errorManager } from '@kit.AbilityKit'
import { common } from '@kit.AbilityKit'

const TAG = 'CrashService'
const DOMAIN = 0x0003

export class CrashService {
  private static initialized: boolean = false

  /**
   * Initialize crash collection. Must be called once in EntryAbility.onCreate().
   */
  static init(context: common.UIAbilityContext): void {
    if (CrashService.initialized) {
      return
    }
    CrashService.initialized = true

    try {
      errorManager.on('error', {
        onUnhandledException(errorMsg: string) {
          hilog.error(DOMAIN, TAG, `UnhandledException: ${errorMsg}`)
        }
      } as errorManager.ErrorObserver)
      hilog.info(DOMAIN, TAG, 'Global error observer registered')
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `Failed to register error observer: ${(e as Error).message}`)
    }

    CrashService.logInfo('App started')
  }

  /**
   * Log a JS error that will appear in crash reports.
   */
  static logJsError(message: string): void {
    hilog.error(DOMAIN, TAG, message)
  }

  /**
   * Log a non-fatal warning.
   */
  static logWarning(message: string): void {
    hilog.warn(DOMAIN, TAG, message)
  }

  /**
   * Log an informational marker.
   */
  static logInfo(message: string): void {
    hilog.info(DOMAIN, TAG, message)
  }

  /**
   * Set user identifier for crash reports so crashes can be tied to specific users.
   */
  static setUserId(userId: string): void {
    hilog.info(DOMAIN, TAG, `Crash user ID set: ${userId}`)
  }
}
