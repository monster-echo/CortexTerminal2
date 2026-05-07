/**
 * @file RestApiClient.ets
 * @brief REST API client using @ohos.net.http
 *
 * Provides typed HTTP methods for terminal session management,
 * worker queries, and auth operations. Uses @ohos.net.http
 * for network communication.
 */
import { http } from '@kit.NetworkKit'
import { SessionInfo, SessionListResponse, SessionCreateRequest, SessionCreateResponse } from '../model/SessionModels'
import { WorkerInfo, WorkerListResponse } from '@rwecho/core'

/**
 * Request body for sending a phone verification code.
 */
class PhoneCodeBody {
  phone: string = ''
}

/**
 * Request body for verifying a phone number.
 */
class PhoneVerifyBody {
  phone: string = ''
  code: string = ''
}

/**
 * Request body for refreshing a token.
 */
class RefreshTokenBody {
  refreshToken: string = ''
}

/**
 * REST API client for CortexTerminal backend.
 * Handles authentication headers, error responses, and data parsing.
 */
export class RestApiClient {
  private get gatewayUrl(): string { return AppStorage.get<string>('gatewayUrl') || '' }
  private get authToken(): string { return AppStorage.get<string>('authToken') || '' }

  /**
   * List all terminal sessions for the current user.
   */
  async listSessions(): Promise<SessionInfo[]> {
    const response = await this.get('/api/sessions') as SessionListResponse
    return response.sessions ?? []
  }

  /**
   * Create a new terminal session.
   */
  async createSession(request: SessionCreateRequest): Promise<SessionCreateResponse> {
    return await this.post('/api/sessions', request as Object) as SessionCreateResponse
  }

  /**
   * Get a specific session by ID.
   */
  async getSession(sessionId: string): Promise<SessionInfo> {
    return await this.get(`/api/sessions/${sessionId}`) as SessionInfo
  }

  /**
   * List all workers.
   */
  async listWorkers(): Promise<WorkerInfo[]> {
    try {
      const response = await this.get('/api/workers') as WorkerListResponse
      return response.workers ?? []
    } catch (e) {
      // Worker module may not be available, return empty
      console.warn('Failed to list workers: ' + (e as Error).message)
      return []
    }
  }

  /**
   * Get a specific worker by ID.
   */
  async getWorker(workerId: string): Promise<WorkerInfo> {
    return await this.get(`/api/workers/${workerId}`) as WorkerInfo
  }

  /**
   * Send a phone verification code.
   */
  async sendPhoneCode(phone: string): Promise<void> {
    const body = new PhoneCodeBody()
    body.phone = phone
    await this.post('/api/auth/phone/send-code', body)
  }

  /**
   * Verify a phone number with code.
   */
  async verifyPhone(phone: string, code: string): Promise<Object> {
    const body = new PhoneVerifyBody()
    body.phone = phone
    body.code = code
    return await this.post('/api/auth/phone/verify', body)
  }

  /**
   * Refresh the auth token.
   */
  async refreshToken(refreshToken: string): Promise<Object> {
    const body = new RefreshTokenBody()
    body.refreshToken = refreshToken
    return await this.post('/api/auth/refresh', body)
  }

  /**
   * Make a GET request.
   */
  private async get(path: string): Promise<Object> {
    const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top'
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()

      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, (err, data) => {
        if (err) {
          reject(new Error(err.message || 'Network request failed'))
          return
        }
        if (data.responseCode === 200) {
          resolve(data.result as Object)
        } else {
          reject(new Error(`Request failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }

  /**
   * Make a POST request.
   */
  private async post(path: string, body: Object): Promise<Object> {
    const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top'
    const url = `${baseUrl}${path}`

    return new Promise<Object>((resolve, reject) => {
      const httpRequest = http.createHttp()

      const postHeaders: Record<string, string> = this.buildHeaders()
      postHeaders['Content-Type'] = 'application/json'

      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: postHeaders,
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
          const errorMsg = (data.result as Record<string, string>)?.message || `Request failed (${data.responseCode})`
          reject(new Error(errorMsg))
        }
        httpRequest.destroy()
      })
    })
  }

  /**
   * Build common HTTP headers including auth.
   */
  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json'
    }
    if (this.authToken.length > 0) {
      headers['Authorization'] = `Bearer ${this.authToken}`
    }
    return headers
  }
}
