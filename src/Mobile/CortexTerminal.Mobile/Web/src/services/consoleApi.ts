import type { NativeBridge } from "../bridge/types"

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
  name: string
  hostname?: string
  operatingSystem?: string
  architecture?: string
  version?: string
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

export interface GatewayInfo {
  version: string
  latestWorkerVersion?: string
  latestGatewayVersion?: string
}

export interface ConsoleApi {
  login(username: string): Promise<{ accessToken: string; username: string }>
  listSessions(): Promise<SessionSummary[]>
  getSession(sessionId: string): Promise<SessionDetail>
  createSession(): Promise<CreateSessionResponse>
  deleteSession(sessionId: string): Promise<void>
  listWorkers(): Promise<WorkerSummary[]>
  getWorker(workerId: string): Promise<WorkerDetail>
  upgradeWorker(workerId: string): Promise<void>
  getGatewayInfo(): Promise<GatewayInfo>
}

type SessionSummaryDto = Omit<SessionSummary, "status"> & {
  status: "Attached" | "DetachedGracePeriod" | "Expired" | "Exited"
}

type WorkerSummaryDto = {
  workerId: string
  name: string
  hostname?: string
  operatingSystem?: string
  architecture?: string
  version?: string
  isOnline: boolean
  sessionCount: number
  lastSeenAtUtc: string
}

type WorkerDetailDto = WorkerSummaryDto & {
  sessions: SessionSummaryDto[]
}

export function createConsoleApi(bridge: NativeBridge): ConsoleApi {
  async function rest<T>(method: string, path: string, body?: unknown): Promise<T> {
    return bridge.request<T>("rest", "*", { method, path, body })
  }

  return {
    async login(username) {
      return bridge.request("auth", "dev.login", { username })
    },
    async listSessions() {
      const sessions = await rest<SessionSummaryDto[]>("GET", "/api/me/sessions")
      return sessions.map(mapSessionSummary)
    },
    async getSession(sessionId) {
      const session = await rest<SessionSummaryDto>("GET", `/api/me/sessions/${encodeURIComponent(sessionId)}`)
      return mapSessionSummary(session)
    },
    createSession() {
      return rest<CreateSessionResponse>("POST", "/api/sessions", {
        runtime: "shell",
        columns: 120,
        rows: 40,
      })
    },
    async deleteSession(sessionId) {
      await rest("DELETE", `/api/me/sessions/${encodeURIComponent(sessionId)}`)
    },
    async listWorkers() {
      const workers = await rest<WorkerSummaryDto[]>("GET", "/api/me/workers")
      return workers.map(mapWorkerSummary)
    },
    async getWorker(workerId) {
      const worker = await rest<WorkerDetailDto>("GET", `/api/me/workers/${encodeURIComponent(workerId)}`)
      return mapWorkerDetail(worker)
    },
    async upgradeWorker(workerId) {
      await rest("POST", `/api/me/workers/${encodeURIComponent(workerId)}/upgrade`)
    },
    async getGatewayInfo() {
      return rest<GatewayInfo>("GET", "/api/gateway/info")
    },
  }
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
    name: worker.name,
    hostname: worker.hostname,
    operatingSystem: worker.operatingSystem,
    architecture: worker.architecture,
    version: worker.version,
    isOnline: worker.isOnline,
    sessionCount: worker.sessionCount,
    lastSeenAt: worker.lastSeenAtUtc,
  }
}

function mapWorkerDetail(dto: WorkerDetailDto): WorkerDetail {
  return {
    ...mapWorkerSummary(dto),
    sessions: dto.sessions.map(mapSessionSummary),
  }
}
