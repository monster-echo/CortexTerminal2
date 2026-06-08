/**
 * @file AuthState.ets
 * @brief Single source of truth for authentication state.
 *
 * All components read auth state through this class.
 * Logout goes through AuthState.clear() — no scattered AppStorage calls.
 */
import { AnalyticsService, AnalyticsEvent } from './AnalyticsService'
import { CrashService } from './CrashService'

interface StoredUserInfo {
  displayName: string
}

export class AuthState {
  static getToken(): string {
    return AppStorage.get<string>('authToken') || ''
  }

  static isLoggedIn(): boolean {
    const loggedIn = AppStorage.get<boolean>('isLoggedIn') || false
    const token = AppStorage.get<string>('authToken') || ''
    return loggedIn && token.length > 0
  }

  static getDisplayName(): string {
    const raw = AppStorage.get<string>('userInfo') || ''
    if (raw.length === 0) {
      return ''
    }
    try {
      return (JSON.parse(raw) as StoredUserInfo).displayName ?? ''
    } catch (e) {
      return ''
    }
  }

  static setSession(token: string, username: string): void {
    if (token.length === 0) {
      throw new Error('No token received')
    }
    AppStorage.set<boolean>('isLoggedIn', true)
    AppStorage.set<string>('authToken', token)
    AppStorage.set<string>('userInfo', JSON.stringify({ displayName: username }))
    console.info(`[AuthState] Session saved: token length=${token.length}, username=${username}`)

    AnalyticsService.onEvent(AnalyticsEvent.USER_LOGIN)
    AnalyticsService.setUserId(username)
    CrashService.setUserId(username)
    CrashService.logInfo('User logged in')
  }

  static clear(): void {
    AnalyticsService.onEvent(AnalyticsEvent.USER_LOGOUT)

    AppStorage.set<string>('authToken', '')
    AppStorage.set<boolean>('isLoggedIn', false)
    AppStorage.set<string>('userInfo', '')
    AppStorage.set<boolean>('authCompleted', false)
  }
}
