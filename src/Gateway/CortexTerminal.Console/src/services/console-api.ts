export interface AuthSession {
  token: string
  username: string
}

export type SessionStatus = 'live' | 'detached' | 'expired' | 'exited'
export type SessionWorkerConnectionStatus = 'matched' | 'stale' | 'offline'

export interface SessionSummary {
  sessionId: string
  workerId: string
  status: SessionStatus
  createdAt: string
  lastActivityAt: string
}

export interface SessionDetail extends SessionSummary {
  columns: number
  rows: number
  attachmentState: 'Attached' | 'DetachedGracePeriod' | 'Expired' | 'Exited'
  attachedClientConnectionId: string | null
  leaseExpiresAt: string | null
  exitCode: number | null
  exitReason: string | null
  replayPending: boolean
  sessionWorkerConnectionId: string
  currentWorkerConnectionId: string | null
  workerConnectionStatus: SessionWorkerConnectionStatus
  workerOnline: boolean
  workerName: string | null
  workerHostname: string | null
  workerOperatingSystem: string | null
  workerArchitecture: string | null
  workerVersion: string | null
  workerLastSeenAt: string | null
}

export interface CreateSessionResponse {
  sessionId: string
  workerId?: string
}

export interface WorkerSummary {
  workerId: string
  name?: string
  hostname?: string
  operatingSystem?: string
  architecture?: string
  version?: string
  address?: string
  isOnline: boolean
  sessionCount: number
  connectedAt?: string
}

export interface WorkerDetail extends WorkerSummary {
  sessions: SessionSummary[]
}

export interface GatewayInfo {
  version: string
  latestWorkerVersion?: string
  latestGatewayVersion?: string
}

export interface MyProfile {
  id: string
  username: string
  email: string
  role: 'admin' | 'user'
  displayName: string | null
  avatarUrl: string | null
}

export interface UserSummary {
  id: string
  name: string
  email: string
  role: 'admin' | 'user'
  status: 'active' | 'disabled'
  avatarUrl?: string
}

export interface AuditLogEntry {
  id: string
  timestamp: string
  userId: string
  userName: string
  action: string
  targetEntity: string
  targetId: string
}

export interface AuditLogResponse {
  entries: AuditLogEntry[]
  totalCount: number
}

export interface GatewayStats {
  connectedClients: number
  onlineWorkers: number
  activeSessions: number
  detachedSessions: number
  totalBytesTransferred: number
  uptimeSeconds: number
  startedAtUtc: string
  totalUsers: number
  totalSessions: number
  allocatedMemoryBytes: number
  gcGen0Collections: number
  gcGen1Collections: number
  gcGen2Collections: number
  threadCount: number
  failedLoginIpCount: number
  httpActiveUserCount: number
  hourlyHistory: HourlyStatsPoint[]
}

export interface MyStats {
  totalSessions: number
  activeSessions: number
  detachedSessions: number
  exitedSessions: number
  totalWorkers: number
  onlineWorkers: number
  bytesTransferred: number
  mostRecentSessionAtUtc: string | null
}

export interface AdminUserActivityUser {
  id: string
  username: string
  displayName: string | null
  avatarUrl: string | null
  role: 'admin' | 'user'
  status: 'active' | 'disabled'
  isOnline: boolean
  lastLoginAtUtc: string | null
  activeSessionCount: number
  bytesTransferredLive: number
  bytesTransferredTotal: number
  lastSessionActivityAtUtc: string | null
}

export interface AdminUserActivitySession {
  sessionId: string
  userId: string
  username: string
  workerId: string
  attachmentState: 'Attached' | 'DetachedGracePeriod' | 'Expired' | 'Exited'
  createdAtUtc: string
  lastActivityAtUtc: string
  bytesTransferredLive: number
  bytesTransferredTotal: number
}

export interface AdminUserActivity {
  onlineUserCount: number
  activeSessionCount: number
  users: AdminUserActivityUser[]
  sessions: AdminUserActivitySession[]
}

export interface HourlyStatsPoint {
  timestamp: string
  connectedClients: number
  onlineWorkers: number
  activeSessions: number
  bytesTransferred: number
}

export interface AuditStats {
  loginTrend: DailyCount[]
  authProviderDistribution: ProviderCount[]
  sessionActivityTrend: DailyCount[]
  topActiveUsers: UserActivity[]
}

export interface DailyCount {
  date: string
  action: string
  count: number
}

export interface ProviderCount {
  provider: string
  count: number
}

export interface UserActivity {
  userId: string
  userName: string
  eventCount: number
}

export interface AdminSessionSummary {
  sessionId: string
  userId: string
  workerId: string
  workerName: string
  status: string
  createdAtUtc: string
  lastActivityAtUtc: string
  name: string | null
}

export interface AdminWorkerSummary {
  workerId: string
  name: string
  hostname: string | null
  operatingSystem: string | null
  architecture: string | null
  version: string | null
  isOnline: boolean
  lastSeenAtUtc: string
  firstConnectedAtUtc: string | null
  ownerUserId: string | null
}

export type ArtifactStatus = 'pending' | 'ready' | 'deleted'
export type ArtifactOrigin = 'console' | 'worker'
export type ArtifactFileCategory =
  | 'image'
  | 'pdf'
  | 'video'
  | 'audio'
  | 'archive'
  | 'code'
  | 'text'
  | 'unknown'

export interface ArtifactInfo {
  id: string
  sessionId: string
  filename: string
  sizeBytes: number
  status: ArtifactStatus
  origin: ArtifactOrigin
  fileCategory: ArtifactFileCategory
  uploadedAt: string
  expiresAt: string
}

export interface UploadUrlResponse {
  artifactId: string
  uploadUrl: string
  s3Key: string
  expiresAt: string
}

export interface DownloadUrlResponse {
  downloadUrl: string
  expiresAt: string
}

export interface ArtifactChangedEvent {
  sessionId: string
  artifactId: string
  changeType: 'created' | 'updated' | 'deleted'
  artifact: ArtifactInfo | null
}

export class ConsoleApiError extends Error {
  constructor(
    message: string,
    public readonly status: number
  ) {
    super(message)
    this.name = 'ConsoleApiError'
  }
}

export interface ConsoleApi {
  login(username: string, password: string): Promise<AuthSession>
  listSessions(): Promise<SessionSummary[]>
  getSession(sessionId: string): Promise<SessionDetail>
  createSession(
    size?: {
      columns: number
      rows: number
    },
    clientRequestId?: string,
    workerId?: string
  ): Promise<CreateSessionResponse>
  terminateSession(sessionId: string): Promise<void>
  deleteSession(sessionId: string): Promise<void>
  listWorkers(): Promise<WorkerSummary[]>
  getWorker(workerId: string): Promise<WorkerDetail>
  listUsers(): Promise<UserSummary[]>
  inviteUser(email: string, role: string): Promise<UserSummary>
  updateUser(userId: string, updates: Partial<Pick<UserSummary, 'role' | 'status'>>): Promise<void>
  deleteUser(userId: string): Promise<void>
  getAuditLog(params: {
    page?: number
    pageSize?: number
    actionType?: string
    userId?: string
    fromDate?: string
    toDate?: string
  }): Promise<AuditLogResponse>
  verifyDeviceCode(userCode: string): Promise<void>
  getGatewayInfo(): Promise<GatewayInfo>
  upgradeWorker(workerId: string): Promise<void>
  getAdminStats(): Promise<GatewayStats>
  getAdminAuditStats(period?: string): Promise<AuditStats>
  getAdminSessions(): Promise<AdminSessionSummary[]>
  getAdminWorkers(): Promise<AdminWorkerSummary[]>
  getMyStats(): Promise<MyStats>
  getAdminUserActivity(): Promise<AdminUserActivity>
  listArtifacts(sessionId: string): Promise<ArtifactInfo[]>
  createArtifactUpload(
    sessionId: string,
    filename: string,
    sizeBytes: number,
    contentSha256?: string
  ): Promise<UploadUrlResponse>
  completeArtifactUpload(
    sessionId: string,
    artifactId: string,
    contentSha256: string
  ): Promise<void>
  getArtifactDownloadUrl(sessionId: string, artifactId: string): Promise<DownloadUrlResponse>
  deleteArtifact(sessionId: string, artifactId: string): Promise<void>
  uploadArtifactToS3(uploadUrl: string, file: Blob): Promise<void>
  getMyProfile(): Promise<MyProfile>
}

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>

type SessionSummaryDto = Omit<SessionSummary, 'status'> & {
  status: 'Attached' | 'DetachedGracePeriod' | 'Expired' | 'Exited'
}

type SessionDetailDto = SessionSummaryDto & {
  columns: number
  rows: number
  attachmentState: 'Attached' | 'DetachedGracePeriod' | 'Expired' | 'Exited'
  attachedClientConnectionId: string | null
  leaseExpiresAt: string | null
  exitCode: number | null
  exitReason: string | null
  replayPending: boolean
  sessionWorkerConnectionId: string
  currentWorkerConnectionId: string | null
  workerConnectionStatus: SessionWorkerConnectionStatus
  workerOnline: boolean
  workerName: string | null
  workerHostname: string | null
  workerOperatingSystem: string | null
  workerArchitecture: string | null
  workerVersion: string | null
  workerLastSeenAt: string | null
}

type WorkerSummaryDto = Omit<WorkerSummary, 'isOnline' | 'sessionCount' | 'connectedAt'> & {
  isOnline: boolean
  sessionCount: number
  lastSeenAtUtc?: string
  version?: string
}

type WorkerDetailDto = WorkerSummaryDto & {
  sessions: SessionSummaryDto[]
}

export function createConsoleApi(
  deps: {
    baseUrl?: string
    fetchFn?: FetchFn
    getToken?: () => string | null
    onUnauthorized?: () => void
    onTokenRefreshed?: (newToken: string) => void
  } = {}
): ConsoleApi {
  const {
    baseUrl = '',
    fetchFn = fetch.bind(globalThis),
    getToken = () => null,
    onUnauthorized,
    onTokenRefreshed,
  } = deps

  let refreshPromise: Promise<string | null> | null = null

  async function tryRefreshToken(): Promise<string | null> {
    if (refreshPromise) return refreshPromise
    refreshPromise = (async () => {
      try {
        const token = getToken()
        if (!token) return null
        const response = await fetchFn(`${baseUrl}/api/auth/refresh`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
        })
        if (!response.ok) return null
        const data = (await response.json()) as { accessToken: string }
        onTokenRefreshed?.(data.accessToken)
        return data.accessToken
      } catch {
        return null
      } finally {
        refreshPromise = null
      }
    })()
    return refreshPromise
  }

  async function buildHeaders(
    init: RequestInit | undefined,
    requiresAuth: boolean,
    tokenOverride?: string
  ) {
    const headers = new Headers(init?.headers)
    if (init?.body && !headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/json')
    }
    const token = tokenOverride ?? getToken()
    if (requiresAuth && token) {
      headers.set('Authorization', `Bearer ${token}`)
    }
    return headers
  }

  const request = async <T>(
    path: string,
    init?: RequestInit,
    requiresAuth = true
  ): Promise<T> => {
    const headers = await buildHeaders(init, requiresAuth)
    const response = await fetchFn(`${baseUrl}${path}`, { ...init, headers })

    if (response.status === 401 && requiresAuth && onTokenRefreshed) {
      const newToken = await tryRefreshToken()
      if (newToken) {
        const retryHeaders = await buildHeaders(init, requiresAuth, newToken)
        const retryResponse = await fetchFn(`${baseUrl}${path}`, {
          ...init,
          headers: retryHeaders,
        })
        if (retryResponse.ok) {
          return (await retryResponse.json()) as T
        }
        throw await createConsoleApiError(
          retryResponse,
          requiresAuth,
          onUnauthorized
        )
      }
    }

    if (!response.ok) {
      throw await createConsoleApiError(response, requiresAuth, onUnauthorized)
    }

    return (await response.json()) as T
  }

  const requestVoid = async (
    path: string,
    init?: RequestInit,
    requiresAuth = true
  ) => {
    const headers = await buildHeaders(init, requiresAuth)
    const response = await fetchFn(`${baseUrl}${path}`, { ...init, headers })

    if (response.status === 401 && requiresAuth && onTokenRefreshed) {
      const newToken = await tryRefreshToken()
      if (newToken) {
        const retryHeaders = await buildHeaders(init, requiresAuth, newToken)
        const retryResponse = await fetchFn(`${baseUrl}${path}`, {
          ...init,
          headers: retryHeaders,
        })
        if (retryResponse.ok) return
        throw await createConsoleApiError(
          retryResponse,
          requiresAuth,
          onUnauthorized
        )
      }
    }

    if (!response.ok) {
      throw await createConsoleApiError(response, requiresAuth, onUnauthorized)
    }
  }

  return {
    async login(username, password) {
      const response = await request<{ accessToken: string }>(
        '/api/auth/password/login',
        {
          method: 'POST',
          body: JSON.stringify({ username, password }),
        },
        false
      )

      return {
        token: response.accessToken,
        username,
      }
    },
    async listSessions() {
      const sessions = await request<SessionSummaryDto[]>('/api/me/sessions')
      return sessions.map(mapSessionSummary)
    },
    async getSession(sessionId) {
      const session = await request<SessionDetailDto>(
        `/api/me/sessions/${encodeURIComponent(sessionId)}`
      )
      return mapSessionDetail(session)
    },
    createSession(size = { columns: 120, rows: 40 }, clientRequestId, workerId) {
      return request<CreateSessionResponse>('/api/sessions', {
        method: 'POST',
        body: JSON.stringify({
          runtime: 'shell',
          columns: size.columns,
          rows: size.rows,
          clientRequestId,
          workerId: workerId || undefined,
        }),
      })
    },
    terminateSession(sessionId) {
      return requestVoid(`/api/me/sessions/${encodeURIComponent(sessionId)}/terminate`, {
        method: 'POST',
      })
    },
    deleteSession(sessionId) {
      return requestVoid(`/api/me/sessions/${encodeURIComponent(sessionId)}`, {
        method: 'DELETE',
      })
    },
    async listWorkers() {
      const workers = await request<WorkerSummaryDto[]>('/api/me/workers')
      return workers.map(mapWorkerSummary)
    },
    async getWorker(workerId) {
      const worker = await request<WorkerDetailDto>(
        `/api/me/workers/${encodeURIComponent(workerId)}`
      )
      return mapWorkerDetail(worker)
    },
    listUsers() {
      return request<UserSummary[]>('/api/users')
    },
    inviteUser(email, role) {
      return request<UserSummary>('/api/users/invite', {
        method: 'POST',
        body: JSON.stringify({ email, role }),
      })
    },
    updateUser(userId, updates) {
      return requestVoid(`/api/users/${encodeURIComponent(userId)}`, {
        method: 'PATCH',
        body: JSON.stringify(updates),
      })
    },
    deleteUser(userId) {
      return requestVoid(`/api/users/${encodeURIComponent(userId)}`, {
        method: 'DELETE',
      })
    },
    getAuditLog(params) {
      const searchParams = new URLSearchParams()
      if (params.page) searchParams.set('page', String(params.page))
      if (params.pageSize) searchParams.set('pageSize', String(params.pageSize))
      if (params.actionType) searchParams.set('actionType', params.actionType)
      if (params.userId) searchParams.set('userId', params.userId)
      if (params.fromDate) searchParams.set('fromDate', params.fromDate)
      if (params.toDate) searchParams.set('toDate', params.toDate)
      const qs = searchParams.toString()
      return request<AuditLogResponse>(`/api/audit-log${qs ? `?${qs}` : ''}`)
    },
    verifyDeviceCode(userCode) {
      return requestVoid('/api/auth/device-flow/verify', {
        method: 'POST',
        body: JSON.stringify({ userCode }),
      })
    },
    getGatewayInfo() {
      return request<GatewayInfo>('/api/gateway/info')
    },
    upgradeWorker(workerId) {
      return requestVoid(`/api/me/workers/${encodeURIComponent(workerId)}/upgrade`, {
        method: 'POST',
      })
    },
    getAdminStats() {
      return request<GatewayStats>('/api/admin/stats')
    },
    getAdminAuditStats(period) {
      return request<AuditStats>(`/api/admin/audit-stats${period ? `?period=${period}` : ''}`)
    },
    getAdminSessions() {
      return request<AdminSessionSummary[]>('/api/admin/sessions')
    },
    getAdminWorkers() {
      return request<AdminWorkerSummary[]>('/api/admin/workers')
    },
    getMyStats() {
      return request<MyStats>('/api/me/stats')
    },
    getAdminUserActivity() {
      return request<AdminUserActivity>('/api/admin/user-activity')
    },
    async listArtifacts(sessionId) {
      return request<ArtifactInfo[]>(
        `/api/sessions/${encodeURIComponent(sessionId)}/artifacts`
      )
    },
    async createArtifactUpload(sessionId, filename, sizeBytes, contentSha256) {
      const body: Record<string, unknown> = { filename, sizeBytes, origin: 'console' }
      if (contentSha256) body.contentSha256 = contentSha256
      return request<UploadUrlResponse>(
        `/api/sessions/${encodeURIComponent(sessionId)}/artifacts`,
        {
          method: 'POST',
          body: JSON.stringify(body),
        }
      )
    },
    async completeArtifactUpload(sessionId, artifactId, contentSha256) {
      await request(
        `/api/sessions/${encodeURIComponent(sessionId)}/artifacts/${encodeURIComponent(artifactId)}/complete`,
        {
          method: 'POST',
          body: JSON.stringify({ artifactId, contentSha256 }),
        }
      )
    },
    async getArtifactDownloadUrl(sessionId, artifactId) {
      return request<DownloadUrlResponse>(
        `/api/sessions/${encodeURIComponent(sessionId)}/artifacts/${encodeURIComponent(artifactId)}/download`
      )
    },
    async deleteArtifact(sessionId, artifactId) {
      await requestVoid(
        `/api/sessions/${encodeURIComponent(sessionId)}/artifacts/${encodeURIComponent(artifactId)}`,
        { method: 'DELETE' }
      )
    },
    async uploadArtifactToS3(uploadUrl, file) {
      const response = await fetchFn(uploadUrl, {
        method: 'PUT',
        body: file,
      })
      if (!response.ok) {
        throw new ConsoleApiError(`S3 upload failed: ${response.status}`, response.status)
      }
    },
    async getMyProfile() {
      return request<MyProfile>('/api/me/profile')
    },
  }
}

async function createConsoleApiError(
  response: Response,
  requiresAuth: boolean,
  onUnauthorized?: () => void
) {
  if (response.status === 401) {
    if (requiresAuth) {
      onUnauthorized?.()
      return new ConsoleApiError('Session expired. Please sign in again.', 401)
    }

    return new ConsoleApiError('Login failed.', 401)
  }

  if (response.status === 403) {
    return new ConsoleApiError('Access denied.', 403)
  }

  if (response.status === 404) {
    return new ConsoleApiError('Not found.', 404)
  }

  let title: string | undefined
  try {
    const payload = (await response.clone().json()) as {
      title?: string
      message?: string
    }
    title = payload.title ?? payload.message
  } catch {
    // Ignore parsing errors and fall back to status text.
  }

  return new ConsoleApiError(
    title || response.statusText || `Request failed: ${response.status}`,
    response.status
  )
}

function mapSessionSummary(session: SessionSummaryDto): SessionSummary {
  return {
    sessionId: session.sessionId,
    workerId: session.workerId,
    status: mapSessionStatus(session.status),
    createdAt: session.createdAt,
    lastActivityAt: session.lastActivityAt,
  }
}

function mapSessionDetail(session: SessionDetailDto): SessionDetail {
  return {
    ...mapSessionSummary(session),
    columns: session.columns,
    rows: session.rows,
    attachmentState: session.attachmentState,
    attachedClientConnectionId: session.attachedClientConnectionId,
    leaseExpiresAt: session.leaseExpiresAt,
    exitCode: session.exitCode,
    exitReason: session.exitReason,
    replayPending: session.replayPending,
    sessionWorkerConnectionId: session.sessionWorkerConnectionId,
    currentWorkerConnectionId: session.currentWorkerConnectionId,
    workerConnectionStatus: session.workerConnectionStatus,
    workerOnline: session.workerOnline,
    workerName: session.workerName,
    workerHostname: session.workerHostname,
    workerOperatingSystem: session.workerOperatingSystem,
    workerArchitecture: session.workerArchitecture,
    workerVersion: session.workerVersion,
    workerLastSeenAt: session.workerLastSeenAt,
  }
}

function mapSessionStatus(status: SessionSummaryDto['status']): SessionStatus {
  switch (status) {
    case 'Attached':
      return 'live'
    case 'DetachedGracePeriod':
      return 'detached'
    case 'Expired':
      return 'expired'
    case 'Exited':
      return 'exited'
  }
}

function mapWorkerSummary(dto: WorkerSummaryDto): WorkerSummary {
  return {
    workerId: dto.workerId,
    name: dto.name,
    hostname: dto.hostname,
    operatingSystem: dto.operatingSystem,
    architecture: dto.architecture,
    version: dto.version,
    address: dto.address,
    isOnline: dto.isOnline,
    sessionCount: dto.sessionCount,
    connectedAt: dto.lastSeenAtUtc,
  }
}

function mapWorkerDetail(dto: WorkerDetailDto): WorkerDetail {
  return {
    ...mapWorkerSummary(dto),
    sessions: dto.sessions.map(mapSessionSummary),
  }
}
