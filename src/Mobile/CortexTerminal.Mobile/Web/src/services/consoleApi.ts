import type { AuthSession } from "./auth"

export type SessionStatus = "live" | "detached" | "expired" | "exited"

export interface SessionSummary {
  sessionId: string
  workerId: string
  status: SessionStatus
  createdAt: string
  lastActivityAt: string
}

export interface SessionDetail extends SessionSummary {}

export interface WorkerSummary {
  workerId: string
  displayName: string
  isOnline: boolean
  sessionCount: number
  lastSeenAt: string
}

export interface WorkerDetail extends WorkerSummary {
  sessions: SessionSummary[]
}

export interface CreateSessionResponse {
  sessionId: string
  workerId?: string
}

export interface ConsoleApi {
  login(username: string): Promise<AuthSession>
  listSessions(): Promise<SessionSummary[]>
  getSession(sessionId: string): Promise<SessionDetail>
  createSession(): Promise<CreateSessionResponse>
  listWorkers(): Promise<WorkerSummary[]>
  getWorker(workerId: string): Promise<WorkerDetail>
}

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>

type SessionSummaryDto = Omit<SessionSummary, "status"> & {
  status: "Attached" | "DetachedGracePeriod" | "Expired" | "Exited"
}

type WorkerSummaryDto = {
  workerId: string
  name: string
  isOnline: boolean
  sessionCount: number
  lastSeenAtUtc: string
}

type WorkerDetailDto = WorkerSummaryDto & {
  sessions: SessionSummaryDto[]
}

export function createConsoleApi(deps: {
  baseUrl?: string
  fetchFn?: FetchFn
  getToken?: () => string | null
  onUnauthorized?: () => void
} = {}): ConsoleApi {
  const {
    baseUrl = "",
    fetchFn = fetch.bind(globalThis),
    getToken = () => null,
    onUnauthorized,
  } = deps

  const request = async <T>(path: string, init?: RequestInit, requiresAuth = true) => {
    const headers = new Headers(init?.headers)
    if (init?.body && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json")
    }

    const token = getToken()
    if (requiresAuth && token) {
      headers.set("Authorization", `Bearer ${token}`)
    }

    const response = await fetchFn(`${baseUrl}${path}`, {
      ...init,
      headers,
    })

    if (!response.ok) {
      throw createConsoleApiError(response.status, requiresAuth, onUnauthorized)
    }

    return (await response.json()) as T
  }

  return {
    async login(username) {
      const response = await request<{ accessToken: string }>(
        "/api/dev/login",
        {
          method: "POST",
          body: JSON.stringify({ username }),
        },
        false
      )

      return {
        token: response.accessToken,
        username,
      }
    },
    async listSessions() {
      const sessions = await request<SessionSummaryDto[]>("/api/me/sessions")
      return sessions.map(mapSessionSummary)
    },
    async getSession(sessionId) {
      const session = await request<SessionSummaryDto>(`/api/me/sessions/${encodeURIComponent(sessionId)}`)
      return mapSessionSummary(session)
    },
    createSession() {
      return request<CreateSessionResponse>("/api/sessions", {
        method: "POST",
        body: JSON.stringify({
          runtime: "shell",
          columns: 120,
          rows: 40,
        }),
      })
    },
    async listWorkers() {
      const workers = await request<WorkerSummaryDto[]>("/api/me/workers")
      return workers.map(mapWorkerSummary)
    },
    async getWorker(workerId) {
      const worker = await request<WorkerDetailDto>(`/api/me/workers/${encodeURIComponent(workerId)}`)
      return {
        ...mapWorkerSummary(worker),
        sessions: worker.sessions.map(mapSessionSummary),
      }
    },
  }
}

function createConsoleApiError(status: number, requiresAuth: boolean, onUnauthorized?: () => void) {
  if (status === 401) {
    if (requiresAuth) {
      onUnauthorized?.()
      return new Error("Session expired. Please sign in again.")
    }

    return new Error("Login failed.")
  }

  if (status === 403) {
    return new Error("Access denied.")
  }

  if (status === 404) {
    return new Error("Not found.")
  }

  return new Error(`Request failed: ${status}`)
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

function mapSessionStatus(status: SessionSummaryDto["status"]): SessionStatus {
  switch (status) {
    case "Attached":
      return "live"
    case "DetachedGracePeriod":
      return "detached"
    case "Expired":
      return "expired"
    case "Exited":
      return "exited"
  }
}

function mapWorkerSummary(worker: WorkerSummaryDto): WorkerSummary {
  return {
    workerId: worker.workerId,
    displayName: worker.name,
    isOnline: worker.isOnline,
    sessionCount: worker.sessionCount,
    lastSeenAt: worker.lastSeenAtUtc,
  }
}
