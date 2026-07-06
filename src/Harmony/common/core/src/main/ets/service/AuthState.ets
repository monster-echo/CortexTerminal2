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
  avatarUrl: string
}

export class AuthState {
  private static avatarBust: number = 0

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

  static getAvatarUrl(): string {
    const raw = AppStorage.get<string>('userInfo') || ''
    if (raw.length === 0) {
      return ''
    }
    try {
      return (JSON.parse(raw) as StoredUserInfo).avatarUrl ?? ''
    } catch (e) {
      return ''
    }
  }

  // Resolve avatarUrl (relative, e.g. /api/users/{id}/avatar) to a fully-qualified
  // URL with a cache-bust query so <Image> reloads after an avatar update.
  static getResolvedAvatarUrl(): string {
    const url = AuthState.getAvatarUrl()
    if (url.length === 0) {
      return ''
    }
    const gw = AppStorage.get<string>('gatewayUrl') || ''
    if (gw.length === 0) {
      return url
    }
    const sep = url.includes('?') ? '&' : '?'
    return `${gw}${url}${sep}t=${AuthState.avatarBust}`
  }

  static updateDisplayName(name: string): void {
    const avatarUrl = AuthState.getAvatarUrl()
    const info: StoredUserInfo = { displayName: name, avatarUrl: avatarUrl }
    AppStorage.set<string>('userInfo', JSON.stringify(info))
  }

  static updateAvatar(url: string): void {
    const displayName = AuthState.getDisplayName()
    const info: StoredUserInfo = { displayName: displayName, avatarUrl: url }
    AppStorage.set<string>('userInfo', JSON.stringify(info))
    AuthState.avatarBust = Date.now()
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
