/**
 * @file ApiService.ets
 * @brief Unified HTTP client for all REST API calls.
 *
 * Handles auth header injection, 401 token refresh retry,
 * and data mapping for sessions, workers, and user profiles.
 */
import { http } from '@kit.NetworkKit'
import { SessionInfo, SessionCreateRequest, SessionCreateResponse } from '../model/SessionModels'
import { WorkerInfo, GatewayInfo, SupportInfo, SupportGroupInfo } from '../model/SharedModels'
import { AuthError, AuthErrorKind } from './AuthError'

export interface FeedbackUploadResult {
  uploadUrl: string
  imageUrl: string
}

export class ApiService {
  private static isRefreshing: boolean = false

  private static get gatewayUrl(): string {
    return AppStorage.get<string>('gatewayUrl') as string
  }

  private static get authToken(): string {
    return AppStorage.get<string>('authToken') || ''
  }

  // ── Session APIs ──────────────────────────────────────────────────

  static async listSessions(): Promise<SessionInfo[]> {
    const response = await ApiService.get('/api/me/sessions') as Object[]
    return response.map((item: Object) => ApiService.mapSession(item))
  }

  static async createSession(request: SessionCreateRequest): Promise<SessionCreateResponse> {
    request.runtime = 'shell'
    if (!request.clientRequestId || request.clientRequestId.length === 0) {
      request.clientRequestId = `harmony-${Date.now()}-${Math.floor(Math.random() * 100000)}`
    }

    const response = await ApiService.post('/api/sessions', request as Object) as Record<string, Object>
    const sessionId = (response['sessionId'] as string) ?? ''
    const result = new SessionCreateResponse()
    result.id = sessionId
    result.sessionId = sessionId
    result.workerId = (response['workerId'] as string) ?? ''
    result.name = (response['name'] as string) || ApiService.shortSessionTitle(sessionId)
    result.status = 'idle'
    result.createdAt = new Date().toISOString()
    return result
  }

  static async getSession(sessionId: string): Promise<SessionInfo> {
    return ApiService.mapSession(
      await ApiService.get(`/api/me/sessions/${encodeURIComponent(sessionId)}`)
    )
  }

  static async deleteSession(sessionId: string): Promise<void> {
    await ApiService.del(`/api/me/sessions/${encodeURIComponent(sessionId)}`)
  }

  static async renameSession(sessionId: string, name: string): Promise<void> {
    const body: Record<string, string> = { 'name': name }
    await ApiService.put(`/api/me/sessions/${encodeURIComponent(sessionId)}`, body as Object)
  }

  // ── Artifact APIs ────────────────────────────────────────────────

  static async listArtifacts(sessionId: string): Promise<Object[]> {
    return await ApiService.get(`/api/sessions/${encodeURIComponent(sessionId)}/artifacts`) as Object[]
  }

  static async createArtifactUpload(sessionId: string, filename: string, sizeBytes: number,
    contentSha256: string): Promise<Record<string, Object>> {
    const body: Record<string, Object> = {
      'filename': filename,
      'sizeBytes': sizeBytes,
      'contentSha256': contentSha256,
      'origin': 'console',
      'sessionId': sessionId
    }
    return await ApiService.post(
      `/api/sessions/${encodeURIComponent(sessionId)}/artifacts`,
      body as Object) as Record<string, Object>
  }

  static async completeArtifactUpload(sessionId: string, artifactId: string,
    contentSha256: string): Promise<void> {
    const body: Record<string, Object> = {
      'artifactId': artifactId,
      'contentSha256': contentSha256
    }
    await ApiService.post(
      `/api/sessions/${encodeURIComponent(sessionId)}/artifacts/${encodeURIComponent(artifactId)}/complete`,
      body as Object)
  }

  static async deleteArtifact(sessionId: string, artifactId: string): Promise<void> {
    await ApiService.del(
      `/api/sessions/${encodeURIComponent(sessionId)}/artifacts/${encodeURIComponent(artifactId)}`)
  }

  static async getArtifactDownloadUrl(sessionId: string, artifactId: string): Promise<string> {
    const resp = await ApiService.get(
      `/api/sessions/${encodeURIComponent(sessionId)}/artifacts/${encodeURIComponent(artifactId)}/download`
    ) as Record<string, Object>
    return (resp['downloadUrl'] as string) ?? ''
  }

  static async putBinaryToS3(uploadUrl: string, buffer: ArrayBuffer): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(uploadUrl, {
        method: http.RequestMethod.PUT,
        header: { 'Content-Type': 'application/octet-stream' },
        extraData: buffer,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000
      }, (err, data) => {
        if (err) {
          reject(new Error((err as Error).message || 'S3 upload failed'))
          return
        }
        if (data.responseCode >= 200 && data.responseCode < 300) {
          resolve()
        } else {
          reject(new Error(`S3 upload failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }

  // ── Worker APIs ───────────────────────────────────────────────────

  static async listWorkers(): Promise<WorkerInfo[]> {
    const response = await ApiService.get('/api/me/workers') as Object[]
    return response.map((item: Object) => ApiService.mapWorker(item))
  }

  static async getWorker(workerId: string): Promise<WorkerInfo> {
    return ApiService.mapWorker(
      await ApiService.get(`/api/me/workers/${encodeURIComponent(workerId)}`)
    )
  }

  static async getGatewayInfo(): Promise<GatewayInfo> {
    const response = await ApiService.get('/api/gateway/info') as Record<string, Object>
    const info = new GatewayInfo()
    info.version = (response['version'] as string) ?? ''
    info.latestWorkerVersion = (response['latestWorkerVersion'] as string) ?? ''
    info.latestGatewayVersion = (response['latestGatewayVersion'] as string) ?? ''
    return info
  }

  static async getSupportInfo(): Promise<SupportInfo> {
    const response = await ApiService.get('/api/support/info', false) as Record<string, Object>
    const info = new SupportInfo()
    info.qqGroup = ApiService.mapSupportGroup(response['qqGroup'])
    info.telegramGroup = ApiService.mapSupportGroup(response['telegramGroup'])
    info.email = (response['email'] as string) ?? ''
    return info
  }

  private static mapSupportGroup(raw: Object | undefined): SupportGroupInfo | null {
    if (!raw) {
      return null
    }
    const data = raw as Record<string, Object>
    const group = new SupportGroupInfo()
    group.name = (data['name'] as string) ?? ''
    group.number = (data['number'] as string) ?? ''
    group.url = (data['url'] as string) ?? ''
    group.qrCodeUrl = (data['qrCodeUrl'] as string) ?? ''
    return group
  }

  static async upgradeWorker(workerId: string): Promise<void> {
    const body: Record<string, string> = {}
    await ApiService.post(`/api/me/workers/${encodeURIComponent(workerId)}/upgrade`, body)
  }

  // ── User APIs ─────────────────────────────────────────────────────

  static async getProfile(): Promise<Record<string, Object>> {
    return await ApiService.get('/api/me/profile') as Record<string, Object>
  }

  static async changePassword(newPassword: string, currentPassword: string): Promise<void> {
    const body: Record<string, Object> = { 'newPassword': newPassword }
    if (currentPassword.length > 0) {
      body['currentPassword'] = currentPassword
    }
    await ApiService.put('/api/me/password', body as Object)
  }

  static async updateProfile(displayName: string): Promise<void> {
    const body: Record<string, Object> = { 'displayName': displayName }
    await ApiService.post('/api/me/profile', body as Object)
  }

  static async uploadAvatar(base64: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const httpRequest = http.createHttp()
      const url = `${ApiService.gatewayUrl}/api/me/avatar`
      const header: Record<string, string> = {
        'Content-Type': 'text/plain',
        'Authorization': `Bearer ${ApiService.authToken}`
      }
      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: base64,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000
      }, (err, data) => {
        if (err) {
          reject(new Error((err as Error).message || 'Avatar upload failed'))
          return
        }
        if (data.responseCode >= 200 && data.responseCode < 300) {
          resolve()
        } else {
          reject(new Error(`Avatar upload failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }

  static async createFeedbackUpload(filename: string): Promise<FeedbackUploadResult> {
    const body: Record<string, Object> = { 'filename': filename }
    const resp = await ApiService.post('/api/me/feedback/uploads', body) as Record<string, Object>
    const uploadUrl = (resp['uploadUrl'] as string) ?? ''
    const rawImageUrl = (resp['imageUrl'] as string) ?? ''
    const imageUrl = rawImageUrl.startsWith('http') ? rawImageUrl : `${ApiService.gatewayUrl}${rawImageUrl}`
    const result: FeedbackUploadResult = { uploadUrl: uploadUrl, imageUrl: imageUrl }
    return result
  }

  static async deleteAccount(): Promise<void> {
    await ApiService.del('/api/me/account')
  }

  // ── Preference APIs ────────────────────────────────────────────────

  static async getScrollbackMaxBytes(): Promise<number> {
    const resp = await ApiService.get('/api/me/preferences') as Record<string, Object>
    return (resp['scrollbackMaxBytes'] as number) ?? 524288
  }

  static async updateScrollbackMaxBytes(maxBytes: number): Promise<void> {
    const body: Record<string, Object> = { 'scrollbackMaxBytes': maxBytes }
    await ApiService.put('/api/me/preferences', body as Object)
  }

  // ── Auth APIs (called by AuthService) ─────────────────────────────

  static async loginWithHuaweiAuthCode(authCode: string, unionID: string, openID: string): Promise<Record<string, Object>> {
    const body: Record<string, string> = {
      'authCode': authCode,
      'unionID': unionID,
      'openID': openID
    }
    return await ApiService.post('/api/auth/huawei/quick-login', body as Object, false) as Record<string, Object>
  }

  static async loginWithPassword(username: string, password: string, captchaToken: string = ''): Promise<Record<string, Object>> {
    const body: Record<string, string> = {
      'username': username,
      'password': password
    }
    if (captchaToken.length > 0) {
      body['captchaToken'] = captchaToken
    }
    return await ApiService.post('/api/auth/password/login', body as Object, false) as Record<string, Object>
  }

  static async getCaptchaChallenge(): Promise<Record<string, Object>> {
    return await ApiService.get('/api/auth/captcha/challenge', false) as Record<string, Object>
  }

  static async verifyCaptcha(id: string, x: number): Promise<string> {
    if (x <= 0) {
      throw new Error('Captcha x must be > 0')
    }
    const body: Record<string, Object> = { 'id': id, 'x': x }
    const resp = await ApiService.post('/api/auth/captcha/verify', body as Object, false) as Record<string, Object>
    const token = (resp['captchaToken'] as string) ?? ''
    if (token.length === 0) {
      throw new Error('No captchaToken in response')
    }
    return token
  }

  static async verifyActivationCode(userCode: string): Promise<void> {
    const body: Record<string, string> = {
      'userCode': userCode
    }
    await ApiService.post('/api/auth/device-flow/verify', body as Object)
  }

  static async refreshToken(token: string): Promise<string> {
    const response = await ApiService.post('/api/auth/refresh', new Object(), false, token) as Record<string, Object>
    const newToken = (response['accessToken'] as string) ?? ''
    if (newToken.length === 0) {
      throw new Error('Empty token in refresh response')
    }
    return newToken
  }

  // ── HTTP primitives ───────────────────────────────────────────────

  private static async get(path: string, requiresAuth: boolean = true, isRetry: boolean = false): Promise<Object> {
    const url = `${ApiService.gatewayUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: ApiService.buildHeaders(requiresAuth),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, async (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200) {
          resolve(data.result as Object)
        } else if (data.responseCode === 401 && requiresAuth && !isRetry) {
          try {
            const retried = await ApiService.handle401AndRetry('GET', path, null, requiresAuth)
            resolve(retried)
          } catch (retryErr) {
            reject(retryErr)
          }
        } else {
          reject(new Error(`Request failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }

  private static async post(path: string, body: Object, requiresAuth: boolean = true, overrideToken?: string, isRetry: boolean = false): Promise<Object> {
    const url = `${ApiService.gatewayUrl}${path}`
    const headers: Record<string, string> = overrideToken
      ? { 'Accept': 'application/json', 'Content-Type': 'application/json', 'Authorization': `Bearer ${overrideToken}` }
      : ApiService.buildHeaders(requiresAuth)
    if (!overrideToken) {
      headers['Content-Type'] = 'application/json'
    }

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, async (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200 || data.responseCode === 201) {
          resolve(data.result as Object)
        } else if (data.responseCode === 401 && requiresAuth && !isRetry) {
          try {
            const retried = await ApiService.handle401AndRetry('POST', path, body, requiresAuth)
            resolve(retried)
          } catch (retryErr) {
            reject(retryErr)
          }
        } else {
          const resultRecord = data.result as Record<string, string>
          const errField = resultRecord?.error ||
            resultRecord?.message ||
            ''
          if (data.responseCode === 403 && errField === 'CAPTCHA_REQUIRED') {
            reject(new AuthError(AuthErrorKind.CAPTCHA_REQUIRED, errField, 403))
          } else {
            reject(new Error(errField.length > 0 ? errField : `Request failed (${data.responseCode})`))
          }
        }
        httpRequest.destroy()
      })
    })
  }

  private static async del(path: string, requiresAuth: boolean = true, isRetry: boolean = false): Promise<Object> {
    const url = `${ApiService.gatewayUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.DELETE,
        header: ApiService.buildHeaders(requiresAuth),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, async (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200 || data.responseCode === 204) {
          resolve(data.result as Object ?? new Object())
        } else if (data.responseCode === 401 && requiresAuth && !isRetry) {
          try {
            const retried = await ApiService.handle401AndRetry('DELETE', path, null, requiresAuth)
            resolve(retried)
          } catch (retryErr) {
            reject(retryErr)
          }
        } else {
          reject(new Error(`Request failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }

  private static async put(path: string, body: Object, requiresAuth: boolean = true,
    isRetry: boolean = false): Promise<Object> {
    const url = `${ApiService.gatewayUrl}${path}`
    const headers: Record<string, string> = ApiService.buildHeaders(requiresAuth)
    headers['Content-Type'] = 'application/json'

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.PUT,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, async (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200) {
          resolve(data.result as Object)
        } else if (data.responseCode === 401 && requiresAuth && !isRetry) {
          try {
            const retried = await ApiService.handle401AndRetry('PUT', path, body, requiresAuth)
            resolve(retried)
          } catch (retryErr) {
            reject(retryErr)
          }
        } else {
          reject(new Error(`Request failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }

  // ── 401 handling ──────────────────────────────────────────────────

  private static async handle401AndRetry(method: string, path: string, body: Object | null,
    requiresAuth: boolean): Promise<Object> {
    console.info(`[ApiService] handle401AndRetry: ${method} ${path}`)
    if (ApiService.isRefreshing) {
      throw new Error('Token refresh already in progress')
    }
    ApiService.isRefreshing = true
    try {
      const currentToken = AppStorage.get<string>('authToken') || ''
      if (currentToken.length === 0) {
        console.info('[ApiService] handle401AndRetry: no token -> forceLogout')
        ApiService.forceLogout()
        throw new Error('Session expired, please login again')
      }
      console.info('[ApiService] handle401AndRetry: refreshing token...')
      const newToken = await ApiService.refreshToken(currentToken)
      AppStorage.set<string>('authToken', newToken)
      console.info('[ApiService] handle401AndRetry: token refreshed, retrying request')

      if (method === 'GET') {
        return await ApiService.get(path, requiresAuth, true)
      } else if (method === 'DELETE') {
        return await ApiService.del(path, requiresAuth, true)
      } else if (method === 'PUT') {
        return await ApiService.put(path, body!, requiresAuth, true)
      } else {
        return await ApiService.post(path, body!, requiresAuth, undefined, true)
      }
    } catch (e) {
      console.info(`[ApiService] handle401AndRetry: failed -> forceLogout: ${(e as Error).message}`)
      ApiService.forceLogout()
      throw new Error((e as Error).message)
    } finally {
      ApiService.isRefreshing = false
    }
  }

  static forceLogout(): void {
    console.info('[ApiService] forceLogout: clearing auth state')
    AppStorage.set<string>('authToken', '')
    AppStorage.set<boolean>('isLoggedIn', false)
    AppStorage.setOrCreate('userInfo', '')
    AppStorage.setOrCreate('authCompleted', false)
  }

  // ── Data mapping ──────────────────────────────────────────────────

  static mapSession(item: Object): SessionInfo {
    const data = item as Record<string, Object>
    const sessionId = (data['sessionId'] as string) ?? (data['id'] as string) ?? ''
    const session = new SessionInfo()
    session.id = sessionId
    session.sessionId = sessionId
    session.name = (data['name'] as string) || ApiService.shortSessionTitle(sessionId)
    session.status = ApiService.mapSessionStatus((data['status'] as string) ?? '')
    session.workerId = (data['workerId'] as string) ?? ''
    session.workerName = (data['workerName'] as string) ?? (data['workerHostname'] as string) ?? ''
    session.createdAt = ApiService.readDate(data['createdAt']) || ApiService.readDate(data['createdAtUtc'])
    session.updatedAt = ApiService.readDate(data['lastActivityAt']) || ApiService.readDate(data['lastActivityAtUtc'])
    session.lastActivityAt = session.updatedAt
    session.lastActiveAt = session.updatedAt
    session.columns = (data['columns'] as number) ?? 80
    session.rows = (data['rows'] as number) ?? 24
    return session
  }

  static mapWorker(item: Object): WorkerInfo {
    const data = item as Record<string, Object>
    const workerId = (data['workerId'] as string) ?? (data['id'] as string) ?? ''
    const isOnline = (data['isOnline'] as boolean) ?? false
    const sessionCount = (data['sessionCount'] as number) ?? 0
    const worker = new WorkerInfo()
    worker.id = workerId
    worker.workerId = workerId
    worker.name = (data['name'] as string) ?? ''
    worker.hostname = (data['hostname'] as string) ?? ''
    worker.status = isOnline ? 'online' : 'offline'
    worker.isOnline = isOnline
    worker.operatingSystem = (data['operatingSystem'] as string) ?? ''
    worker.os = worker.operatingSystem
    worker.architecture = (data['architecture'] as string) ?? ''
    worker.arch = worker.architecture
    worker.version = (data['version'] as string) ?? ''
    worker.address = (data['address'] as string) ?? ''
    worker.activeSessions = sessionCount
    worker.sessionCount = sessionCount
    worker.maxSessions = Math.max(sessionCount, 1)
    worker.cpuUsage = (data['cpuUsagePercent'] as number) ?? 0
    worker.memoryUsage = (data['memoryUsagePercent'] as number) ?? 0
    worker.lastSeenAt = ApiService.readDate(data['lastSeenAtUtc'])
    return worker
  }

  private static mapSessionStatus(status: string): string {
    switch (status) {
      case 'Attached':
        return 'running'
      case 'DetachedGracePeriod':
        return 'idle'
      case 'Exited':
      case 'Expired':
        return 'failed'
      default:
        return status.length > 0 ? status.toLowerCase() : 'idle'
    }
  }

  static shortSessionTitle(sessionId: string): string {
    if (sessionId.length === 0) {
      return 'Terminal'
    }
    return sessionId.length <= 12 ? sessionId : `session ${sessionId.substring(0, 8)}`
  }

  private static readDate(value: Object | undefined): string {
    if (!value) {
      return ''
    }
    return value as string
  }

  private static buildHeaders(requiresAuth: boolean = true): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json'
    }
    if (requiresAuth && ApiService.authToken.length > 0) {
      headers['Authorization'] = `Bearer ${ApiService.authToken}`
    }
    return headers
  }
}
