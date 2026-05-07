/**
 * @file AuthService.ets
 * @brief Authentication state management and token storage
 *
 * Manages auth state using PersistentStorage for persistence and
 * AppStorage for reactive UI updates. Provides login, logout,
 * token refresh, and OAuth flow management.
 */
import { http } from '@kit.NetworkKit'
import { preferences } from '@kit.ArkData'
import { common, Want } from '@kit.AbilityKit'
import {
  PhoneSendCodeRequest,
  PhoneVerifyRequest,
  PhoneVerifyResponse,
  TokenData,
  UserInfo,
  OAuthCallbackRequest,
  WorkerActivateRequest,
  TokenRefreshRequest
} from '../model/AuthModels'

const AUTH_PREFERENCE = 'auth_prefs'
const KEY_AUTH_TOKEN = 'auth_token'
const KEY_REFRESH_TOKEN = 'refresh_token'
const KEY_USER_INFO = 'user_info'

/**
 * Authentication service singleton.
 * Uses PersistentStorage for cross-session persistence and
 * AppStorage for reactive state management.
 */
export class AuthService {
  private get authToken(): string { return AppStorage.get<string>('authToken') || '' }
  private set authToken(value: string) { AppStorage.setOrCreate('authToken', value) }
  private get storedRefreshToken(): string { return AppStorage.get<string>('refreshToken') || '' }
  private set storedRefreshToken(value: string) { AppStorage.setOrCreate('refreshToken', value) }
  private get loggedIn(): boolean { return AppStorage.get<boolean>('isLoggedIn') || false }
  private set loggedIn(value: boolean) { AppStorage.setOrCreate('isLoggedIn', value) }
  private get userInfoStr(): string { return AppStorage.get<string>('userInfo') || '' }
  private set userInfoStr(value: string) { AppStorage.setOrCreate('userInfo', value) }
  private get gatewayUrl(): string { return AppStorage.get<string>('gatewayUrl') || '' }
  private set gatewayUrl(value: string) { AppStorage.setOrCreate('gatewayUrl', value) }

  /**
   * Check if the user is currently authenticated.
   */
  isLoggedIn(): boolean {
    return this.loggedIn && this.authToken.length > 0
  }

  /**
   * Get the current auth token.
   */
  getToken(): string {
    return this.authToken
  }

  /**
   * Get the current user info.
   */
  getUserInfo(): UserInfo | null {
    if (this.userInfoStr.length === 0) {
      return null
    }
    try {
      return JSON.parse(this.userInfoStr) as UserInfo
    } catch (e) {
      return null
    }
  }

  /**
   * Send a verification code to the given phone number.
   */
  async sendVerificationCode(phone: string): Promise<void> {
    const request = new PhoneSendCodeRequest()
    request.phone = phone
    await this.post('/api/auth/phone/send-code', request)
  }

  /**
   * Login with phone number and verification code.
   * Stores tokens on success.
   */
  async login(phone: string, code: string): Promise<void> {
    const request = new PhoneVerifyRequest()
    request.phone = phone
    request.code = code
    const response = await this.post('/api/auth/phone/verify', request) as Record<string, Object>

    this.authToken = (response['accessToken'] as string) ?? ''
    this.loggedIn = true
  }

  /**
   * Start an OAuth flow for the given provider.
   * Opens the system browser to the gateway's OAuth authorize endpoint.
   */
  async startOAuth(provider: string): Promise<void> {
    const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top'
    const oauthUrl = `${baseUrl}/api/auth/${provider}`
    try {
      const context = getContext(this) as common.UIAbilityContext
      const want = new Want()
      want.action = 'ohos.want.action.viewData'
      want.uri = oauthUrl
      await context.startAbility(want)
    } catch (e) {
      console.warn('Failed to open OAuth URL: ' + (e as Error).message)
    }
  }

  /**
   * Handle OAuth callback — the gateway handles this server-side
   * via 302 redirect back to the app with ?token=<jwt>.
   * This method stores the token received from the redirect.
   */
  async handleOAuthToken(token: string): Promise<void> {
    this.authToken = token
    this.loggedIn = true
  }

  /**
   * Login as guest. Creates a temporary guest account on the gateway.
   */
  async loginAsGuest(): Promise<void> {
    const response = await this.post('/api/auth/guest', {}) as Record<string, Object>
    this.authToken = (response['accessToken'] as string) ?? ''
    this.loggedIn = true
  }

  /**
   * Login with Huawei one-click login authCode.
   * Sends the authCode, unionID, openID to the gateway for server-side
   * token exchange and phone number retrieval.
   */
  async loginWithHuaweiAuthCode(authCode: string, unionID: string, openID: string): Promise<void> {
    const body: Record<string, string> = {
      'authCode': authCode,
      'unionID': unionID,
      'openID': openID
    }
    const response = await this.post('/api/auth/huawei/quick-login', body as Object) as Record<string, Object>

    this.authToken = (response['accessToken'] as string) ?? ''
    this.loggedIn = true
  }

  /**
   * Activate a worker with the given activation code.
   */
  async activateWorker(activationCode: string): Promise<void> {
    const requestBody = new WorkerActivateRequest()
    requestBody.code = activationCode
    await this.post('/api/workers/activate', requestBody)
  }

  /**
   * Refresh the authentication token.
   */
  async refreshToken(): Promise<void> {
    if (this.storedRefreshToken.length === 0) {
      throw new Error('No refresh token available')
    }

    const requestBody = new TokenRefreshRequest()
    requestBody.refreshToken = this.storedRefreshToken
    const response = await this.post('/api/auth/refresh', requestBody) as Record<string, Object>

    this.authToken = (response['accessToken'] as string) ?? ''
  }

  /**
   * Logout and clear all stored credentials.
   */
  logout(): void {
    this.authToken = ''
    this.storedRefreshToken = ''
    this.loggedIn = false
    this.userInfoStr = ''
  }

  /**
   * Complete authentication flow, signaling that auth is done.
   * The navigation shell will pick up the state change via AppStorage.
   */
  completeAuth(): void {
    // The shell Navigation watches 'isLoggedIn' to navigate away from auth
    AppStorage.setOrCreate('authCompleted', true)
  }

  /**
   * Make a POST request to the auth API.
   */
  private async post(path: string, body: Object): Promise<Object> {
    const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top'
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      }

      if (this.authToken.length > 0) {
        headers['Authorization'] = `Bearer ${this.authToken}`
      }

      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200 || data.responseCode === 201) {
          resolve(data.result as Object)
        } else {
          const errorMsg = (data.result as Record<string, string>)?.error ||
            (data.result as Record<string, string>)?.message ||
            `Request failed (${data.responseCode})`
          reject(new Error(errorMsg))
        }
        httpRequest.destroy()
      })
    })
  }
}
