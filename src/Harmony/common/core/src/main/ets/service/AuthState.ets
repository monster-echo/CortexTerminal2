/**
 * @file AuthState.ets
 * @brief Single source of truth for authentication state.
 *
 * All components read auth state through this class.
 * Logout goes through AuthState.clear() — no scattered AppStorage calls.
 */

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
    AppStorage.setOrCreate('authToken', token)
    AppStorage.setOrCreate('isLoggedIn', true)
    AppStorage.setOrCreate('userInfo', JSON.stringify({ displayName: username }))
    console.info(`[AuthState] Session saved: token length=${token.length}, username=${username}`)
  }

  static clear(): void {
    AppStorage.setOrCreate('authToken', '')
    AppStorage.setOrCreate('isLoggedIn', false)
    AppStorage.setOrCreate('userInfo', '')
    AppStorage.setOrCreate('authCompleted', false)
  }
}
