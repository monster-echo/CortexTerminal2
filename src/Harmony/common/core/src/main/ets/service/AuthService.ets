/**
 * @file AuthService.ets
 * @brief Single authentication authority for the entire app.
 *
 * Handles login flows, token refresh, logout, and navigation.
 * UI-specific logic stays in the auth feature module.
 */
import { ApiService } from './ApiService'
import { AuthState } from './AuthState'

export class AuthService {
  static async loginWithHuaweiAuthCode(authCode: string, unionID: string, openID: string): Promise<void> {
    const response = await ApiService.loginWithHuaweiAuthCode(authCode, unionID, openID)
    AuthState.setSession((response['accessToken'] as string) ?? '', (response['username'] as string) ?? 'huawei')
  }

  static async loginWithPassword(username: string, password: string, captchaToken: string = ''): Promise<void> {
    const response = await ApiService.loginWithPassword(username, password, captchaToken)
    AuthState.setSession((response['accessToken'] as string) ?? '', (response['username'] as string) ?? username)
  }

  static async getCaptchaChallenge(): Promise<Record<string, Object>> {
    return await ApiService.getCaptchaChallenge()
  }

  static async verifyCaptcha(id: string, x: number): Promise<string> {
    return await ApiService.verifyCaptcha(id, x)
  }

  static async activateWorker(activationCode: string): Promise<void> {
    await ApiService.verifyActivationCode(activationCode)
  }

  static async ensureAuthenticated(): Promise<boolean> {
    const token = AuthState.getToken()
    console.info(`[AuthService] ensureAuthenticated: token=${token.length > 0 ? 'yes' : 'no'}`)
    if (token.length === 0) {
      return false
    }
    try {
      const newToken = await ApiService.refreshToken(token)
      AppStorage.set<string>('authToken', newToken)
      console.info('[AuthService] Token refreshed, new 7-day validity')
      return true
    } catch (e) {
      console.warn('[AuthService] Token refresh failed: ' + (e as Error).message)
      return false
    }
  }

  static logout(): void {
    AuthState.clear()
  }

  static navigateHome(pageStack: NavPathStack): void {
    AppStorage.setOrCreate('authCompleted', true)
    pageStack.replacePath({ name: 'session/Home' })
  }
}
