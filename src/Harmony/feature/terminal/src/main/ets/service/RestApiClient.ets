/**
 * @file RestApiClient.ets
 * @brief REST API client aligned with the MAUI/mobile gateway contract.
 */
import { http } from '@kit.NetworkKit'
import { SessionInfo, SessionCreateRequest, SessionCreateResponse } from '../model/SessionModels'
import { WorkerInfo } from '@rwecho/core'

export class RestApiClient {
  private get gatewayUrl(): string { return AppStorage.get<string>('gatewayUrl') || '' }
  private get authToken(): string { return AppStorage.get<string>('authToken') || '' }
  private static isRefreshing: boolean = false

  async listSessions(): Promise<SessionInfo[]> {
    const response = await this.get('/api/me/sessions') as Object[]
    return response.map((item: Object) => this.mapSession(item))
  }

  async createSession(request: SessionCreateRequest): Promise<SessionCreateResponse> {
    request.runtime = 'shell'
    if (!request.clientRequestId || request.clientRequestId.length === 0) {
      request.clientRequestId = `harmony-${Date.now()}-${Math.floor(Math.random() * 100000)}`
    }

    const response = await this.post('/api/sessions', request as Object) as Record<string, Object>
    const sessionId = (response['sessionId'] as string) ?? ''
    const result = new SessionCreateResponse()
    result.id = sessionId
    result.sessionId = sessionId
    result.workerId = (response['workerId'] as string) ?? ''
    result.name = this.shortSessionTitle(sessionId)
    result.status = 'idle'
    result.createdAt = new Date().toISOString()
    return result
  }

  async getSession(sessionId: string): Promise<SessionInfo> {
    return this.mapSession(await this.get(`/api/me/sessions/${encodeURIComponent(sessionId)}`))
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.httpDelete(`/api/me/sessions/${encodeURIComponent(sessionId)}`)
  }

  async getProfile(): Promise<Record<string, Object>> {
    const response = await this.get('/api/me/profile') as Record<string, Object>
    return response
  }

  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    const body: Record<string, Object> = {
      'currentPassword': currentPassword,
      'newPassword': newPassword
    }
    await this.post('/api/me/password/change', body as Object)
  }

  async listWorkers(): Promise<WorkerInfo[]> {
    try {
      const response = await this.get('/api/me/workers') as Object[]
      return response.map((item: Object) => this.mapWorker(item))
    } catch (e) {
      console.warn('Failed to list workers: ' + (e as Error).message)
      return []
    }
  }

  async getWorker(workerId: string): Promise<WorkerInfo> {
    return this.mapWorker(await this.get(`/api/me/workers/${encodeURIComponent(workerId)}`))
  }

  private async get(path: string, requiresAuth: boolean = true, isRetry: boolean = false): Promise<Object> {
    const baseUrl = this.gatewayUrl
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(requiresAuth),
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
            const retried = await this.handle401AndRetry('GET', path, null, requiresAuth)
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

  private async post(path: string, body: Object, requiresAuth: boolean = true, isRetry: boolean = false): Promise<Object> {
    const baseUrl = this.gatewayUrl
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      const headers: Record<string, string> = this.buildHeaders(requiresAuth)
      headers['Content-Type'] = 'application/json'

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
            const retried = await this.handle401AndRetry('POST', path, body, requiresAuth)
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

  private async httpDelete(path: string, requiresAuth: boolean = true, isRetry: boolean = false): Promise<Object> {
    const baseUrl = this.gatewayUrl
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.DELETE,
        header: this.buildHeaders(requiresAuth),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, async (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200 || data.responseCode === 204) {
          const result: Object = data.result as Object ?? new Object()
          resolve(result)
        } else if (data.responseCode === 401 && requiresAuth && !isRetry) {
          try {
            const retried = await this.handle401AndRetry('DELETE', path, null, requiresAuth)
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

  private async handle401AndRetry(method: string, path: string, body: Object | null,
    requiresAuth: boolean): Promise<Object> {
    if (RestApiClient.isRefreshing) {
      throw new Error('Token refresh already in progress')
    }
    RestApiClient.isRefreshing = true
    try {
      const refreshed = await this.tryRefreshToken()
      if (!refreshed) {
        this.forceLogout()
        throw new Error('Session expired, please login again')
      }
      if (method === 'GET') {
        return await this.get(path, requiresAuth, true)
      } else if (method === 'DELETE') {
        return await this.httpDelete(path, requiresAuth, true)
      } else {
        return await this.post(path, body!, requiresAuth, true)
      }
    } finally {
      RestApiClient.isRefreshing = false
    }
  }

  private async tryRefreshToken(): Promise<boolean> {
    const token = AppStorage.get<string>('authToken') || ''
    if (token.length === 0) {
      return false
    }
    const baseUrl = this.gatewayUrl
    const url = `${baseUrl}/api/auth/refresh`

    return new Promise<boolean>((resolve) => {
      const httpRequest = http.createHttp()
      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify({}),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 10000,
        readTimeout: 10000
      }, (err, data) => {
        if (err) {
          resolve(false)
          return
        }
        if (data.responseCode === 200) {
          const result = data.result as Record<string, string>
          const newToken = result['accessToken'] ?? ''
          if (newToken.length > 0) {
            AppStorage.setOrCreate('authToken', newToken)
            console.info('[RestApiClient] Token refreshed on 401')
            resolve(true)
            return
          }
        }
        resolve(false)
        httpRequest.destroy()
      })
    })
  }

  private forceLogout() {
    console.warn('[RestApiClient] Token refresh failed, forcing logout')
    AppStorage.setOrCreate('authToken', '')
    AppStorage.setOrCreate('isLoggedIn', false)
    AppStorage.setOrCreate('userInfo', '')
    AppStorage.setOrCreate('refreshToken', '')
    AppStorage.setOrCreate('authCompleted', false)
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

  private mapSession(item: Object): SessionInfo {
    const data = item as Record<string, Object>
    const sessionId = (data['sessionId'] as string) ?? (data['id'] as string) ?? ''
    const session = new SessionInfo()
    session.id = sessionId
    session.sessionId = sessionId
    session.name = this.shortSessionTitle(sessionId)
    session.status = this.mapSessionStatus((data['status'] as string) ?? '')
    session.workerId = (data['workerId'] as string) ?? ''
    session.createdAt = this.readDate(data['createdAt']) || this.readDate(data['createdAtUtc'])
    session.updatedAt = this.readDate(data['lastActivityAt']) || this.readDate(data['lastActivityAtUtc'])
    session.lastActivityAt = session.updatedAt
    session.lastActiveAt = session.updatedAt
    session.columns = (data['columns'] as number) ?? 80
    session.rows = (data['rows'] as number) ?? 24
    return session
  }

  private mapWorker(item: Object): WorkerInfo {
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
    worker.lastSeenAt = this.readDate(data['lastSeenAtUtc'])
    return worker
  }

  private mapSessionStatus(status: string): string {
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

  private shortSessionTitle(sessionId: string): string {
    if (sessionId.length === 0) {
      return 'Terminal'
    }
    return sessionId.length <= 12 ? sessionId : `session ${sessionId.substring(0, 8)}`
  }

  private readDate(value: Object | undefined): string {
    if (!value) {
      return ''
    }
    return value as string
  }
}
