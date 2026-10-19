/**
 * @file AuthService.ets
 * @brief Single authentication authority for the entire app.
 *
 * Handles login flows, token refresh, logout, and navigation.
 * UI-specific logic stays in the auth feature module.
 */
import { ApiService } from './ApiService'
import { AuthState } from './AuthState'
import { RouteName } from '../constants/RouteName'

export class AuthService {
  private static async saveSession(response: Record<string, Object>, fallbackName: string): Promise<void> {
    AuthState.setSession((response['accessToken'] as string) ?? '', (response['username'] as string) ?? fallbackName)
    // Login response only carries username; fetch profile once to persist avatarUrl.
    const profile = await ApiService.getProfile()
    const av = (profile['avatarUrl'] as string) ?? ''
    if (av.length > 0) {
      AuthState.updateAvatar(av)
    }
    const dn = (profile['displayName'] as string) ?? ''
    if (dn.length > 0) {
      AuthState.updateDisplayName(dn)
    }
  }

  static async loginWithHuaweiAuthCode(authCode: string, unionID: string, openID: string): Promise<void> {
    const response = await ApiService.loginWithHuaweiAuthCode(authCode, unionID, openID)
    await AuthService.saveSession(response, 'huawei')
  }

  static async loginWithPassword(username: string, password: string, captchaToken: string = ''): Promise<void> {
    const response = await ApiService.loginWithPassword(username, password, captchaToken)
    await AuthService.saveSession(response, username)
  }

  static async signupWithPassword(username: string, password: string, captchaToken: string = ''): Promise<void> {
    const response = await ApiService.signupWithPassword(username, password, captchaToken)
    await AuthService.saveSession(response, username)
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

  static async updateDisplayName(name: string): Promise<void> {
    await ApiService.updateProfile(name)
    AuthState.updateDisplayName(name)
  }

  static async uploadAvatar(base64: string): Promise<void> {
    await ApiService.uploadAvatar(base64)
    const profile = await ApiService.getProfile()
    const avatarUrl = (profile['avatarUrl'] as string) ?? ''
    AuthState.updateAvatar(avatarUrl)
  }

  static logout(): void {
    AuthState.clear()
  }

  static navigateHome(pageStack: NavPathStack): void {
    AppStorage.setOrCreate('authCompleted', true)
    pageStack.clear()
    pageStack.replacePath({ name: RouteName.SESSION_HOME })
  }

  static finishWorkerActivation(pageStack: NavPathStack, route: string): void {
    const names = pageStack.getAllPathName()
    if (names[names.length - 1] !== route) return
    // Activation is a child flow; successful login alone resets the app root.
    let sourceIndex = names.length - 2
    while (sourceIndex >= 0 && (names[sourceIndex] === RouteName.ACTIVATE_WORKER
      || names[sourceIndex] === RouteName.ACTIVATE_CODE)) {
      sourceIndex--
    }
    if (sourceIndex >= 0) {
      pageStack.popToIndex(sourceIndex)
    } else {
      AuthService.navigateHome(pageStack)
    }
  }
}
