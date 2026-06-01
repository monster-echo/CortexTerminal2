/**
 * @file AuthService.ets
 * @brief Authentication state management aligned with MAUI/mobile.
 */
import { http } from '@kit.NetworkKit'

import { UserInfo, TokenRefreshRequest } from '../model/AuthModels'

class HuaweiQuickLoginRequest {
  authCode: string = ''
  unionID: string = ''
  openID: string = ''
}

class PasswordLoginRequest {
  username: string = ''
  password: string = ''
}

class DeviceFlowVerifyRequest {
  userCode: string = ''
}

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

  isLoggedIn(): boolean {
    return this.loggedIn && this.authToken.length > 0
  }

  getToken(): string {
    return this.authToken
  }

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

  async loginWithHuaweiAuthCode(authCode: string, unionID: string, openID: string): Promise<void> {
    const body = new HuaweiQuickLoginRequest()
    body.authCode = authCode
    body.unionID = unionID
    body.openID = openID
    const response = await this.post('/api/auth/huawei/quick-login', body, false) as Record<string, Object>
    this.setSession((response['accessToken'] as string) ?? '', (response['username'] as string) ?? 'huawei')
  }

  async loginWithPassword(username: string, password: string): Promise<void> {
    const body = new PasswordLoginRequest()
    body.username = username
    body.password = password
    const response = await this.post('/api/auth/password/login', body, false) as Record<string, Object>
    this.setSession((response['accessToken'] as string) ?? '', (response['username'] as string) ?? username)
  }

  async activateWorker(activationCode: string): Promise<void> {
    const request = new DeviceFlowVerifyRequest()
    request.userCode = activationCode
    await this.post('/api/auth/device-flow/verify', request)
  }

  async refreshToken(): Promise<boolean> {
    if (this.storedRefreshToken.length === 0) {
      return false
    }
    try {
      const body = new TokenRefreshRequest()
      body.refreshToken = this.storedRefreshToken
      const response = await this.post('/api/auth/refresh', body) as Record<string, Object>
      const newToken = (response['accessToken'] as string) ?? ''
      if (newToken.length > 0) {
        this.authToken = newToken
        console.info('[AuthService] Token refreshed successfully')
        return true
      }
      return false
    } catch (e) {
      console.warn('[AuthService] Token refresh failed: ' + (e as Error).message)
      return false
    }
  }

  async validateToken(): Promise<boolean> {
    if (this.authToken.length === 0) {
      return false
    }
    try {
      await this.get('/api/me/workers')
      return true
    } catch (e) {
      return false
    }
  }

  async ensureAuthenticated(): Promise<boolean> {
    if (!this.isLoggedIn()) {
      return false
    }
    const valid = await this.validateToken()
    if (valid) {
      return true
    }
    return await this.refreshToken()
  }

  logout(): void {
    this.authToken = ''
    this.storedRefreshToken = ''
    this.loggedIn = false
    this.userInfoStr = ''
  }

  static navigateHome(pageStack: NavPathStack): void {
    AppStorage.setOrCreate('authCompleted', true)
    pageStack.replacePath({ name: 'TerminalHome' })
  }

  private setSession(token: string, username: string): void {
    if (token.length === 0) {
      throw new Error('No token received')
    }
    this.authToken = token
    this.loggedIn = true
    this.userInfoStr = JSON.stringify({ displayName: username })
    console.info(`[AuthService] Session saved: token length=${token.length}, username=${username}`)
  }

  private async post(path: string, body: Object, requiresAuth: boolean = true): Promise<Object> {
    const baseUrl = this.gatewayUrl
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      const headers = this.buildHeaders(requiresAuth)
      headers['Content-Type'] = 'application/json'

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

  private async get(path: string): Promise<Object> {
    const baseUrl = this.gatewayUrl
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      const headers = this.buildHeaders(true)

      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 10000,
        readTimeout: 10000
      }, (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200) {
          resolve(data.result as Object)
        } else {
          reject(new Error(`GET ${path} failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }

  private buildHeaders(requiresAuth: boolean = true): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json'
    }
    if (requiresAuth && this.authToken.length > 0) {
      headers['Authorization'] = `Bearer ${this.authToken}`
    }
    return headers
  }

}
