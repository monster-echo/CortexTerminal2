/**
 * @file ApiService.ets
 * @brief Unified HTTP client for all REST API calls.
 *
 * Handles auth header injection, 401 token refresh retry,
 * and data mapping for sessions, workers, and user profiles.
 */
import { http } from '@kit.NetworkKit'
import { SessionInfo, SessionCreateRequest, SessionCreateResponse } from '../model/SessionModels'
import { WorkerInfo, GatewayInfo } from '../model/SharedModels'

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

  static async deleteAccount(): Promise<void> {
    await ApiService.del('/api/me/account')
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

  static async loginWithPassword(username: string, password: string): Promise<Record<string, Object>> {
    const body: Record<string, string> = {
      'username': username,
      'password': password
    }
    return await ApiService.post('/api/auth/password/login', body as Object, false) as Record<string, Object>
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
          const errorMsg = (data.result as Record<string, string>)?.error ||
            (data.result as Record<string, string>)?.message ||
            `Request failed (${data.responseCode})`
          reject(new Error(errorMsg))
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
