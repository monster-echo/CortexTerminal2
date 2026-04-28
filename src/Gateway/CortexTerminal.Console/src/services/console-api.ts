export interface AuthSession {
  token: string
  username: string
}

export type SessionStatus = 'live' | 'detached' | 'expired' | 'exited'

export interface SessionSummary {
  sessionId: string
  workerId: string
  status: SessionStatus
  createdAt: string
  lastActivityAt: string
}

export type SessionDetail = SessionSummary

export interface CreateSessionResponse {
  sessionId: string
  workerId?: string
}

export interface WorkerSummary {
  workerId: string
  name?: string
  address?: string
  isOnline: boolean
  sessionCount: number
  connectedAt?: string
}

export interface WorkerDetail extends WorkerSummary {
  sessions: SessionSummary[]
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
    clientRequestId?: string
  ): Promise<CreateSessionResponse>
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
}

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>

type SessionSummaryDto = Omit<SessionSummary, 'status'> & {
  status: 'Attached' | 'DetachedGracePeriod' | 'Expired' | 'Exited'
}

type WorkerSummaryDto = Omit<WorkerSummary, 'isOnline' | 'sessionCount'> & {
  isOnline: boolean
  sessionCount: number
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
  } = {}
): ConsoleApi {
  const {
    baseUrl = '',
    fetchFn = fetch.bind(globalThis),
    getToken = () => null,
    onUnauthorized,
  } = deps

  const request = async <T>(
    path: string,
    init?: RequestInit,
    requiresAuth = true
  ) => {
    const headers = new Headers(init?.headers)
    if (init?.body && !headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/json')
    }

    const token = getToken()
    if (requiresAuth && token) {
      headers.set('Authorization', `Bearer ${token}`)
    }

    const response = await fetchFn(`${baseUrl}${path}`, {
      ...init,
      headers,
    })

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
    const headers = new Headers(init?.headers)

    const token = getToken()
    if (requiresAuth && token) {
      headers.set('Authorization', `Bearer ${token}`)
    }

    const response = await fetchFn(`${baseUrl}${path}`, {
      ...init,
      headers,
    })

    if (!response.ok) {
      throw await createConsoleApiError(response, requiresAuth, onUnauthorized)
    }
  }

  return {
    async login(username, password) {
      const response = await request<{ accessToken: string }>(
        '/api/dev/login',
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
      const session = await request<SessionSummaryDto>(
        `/api/me/sessions/${encodeURIComponent(sessionId)}`
      )
      return mapSessionSummary(session)
    },
    createSession(size = { columns: 120, rows: 40 }, clientRequestId) {
      return request<CreateSessionResponse>('/api/sessions', {
        method: 'POST',
        body: JSON.stringify({
          runtime: 'shell',
          columns: size.columns,
          rows: size.rows,
          clientRequestId,
        }),
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
    address: dto.address,
    isOnline: dto.isOnline,
    sessionCount: dto.sessionCount,
    connectedAt: dto.connectedAt,
  }
}

function mapWorkerDetail(dto: WorkerDetailDto): WorkerDetail {
  return {
    ...mapWorkerSummary(dto),
    sessions: dto.sessions.map(mapSessionSummary),
  }
}
