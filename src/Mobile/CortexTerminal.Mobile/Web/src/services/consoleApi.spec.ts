import { describe, expect, it } from "vitest"
import { createConsoleApi } from "./consoleApi"
import type { NativeBridge } from "../bridge/types"

function createMockBridge(responses: Record<string, unknown> = {}): NativeBridge {
  const handlers = new Map<string, Set<(payload: unknown) => void>>()

  return {
    async request<T>(channel: string, method: string, payload?: unknown): Promise<T> {
      const key = `${channel}:${method}`
      // For REST wildcard, use path from payload
      if (channel === "rest" && method === "*") {
        const path = (payload as { path?: string })?.path ?? ""
        const resp = responses[path]
        if (resp !== undefined) return resp as T
        return [] as unknown as T
      }
      const resp = responses[key]
      if (resp !== undefined) return resp as T
      return undefined as unknown as T
    },
    onEvent(channel: string, method: string, handler: (payload: unknown) => void): () => void {
      const key = `${channel}:${method}`
      if (!handlers.has(key)) handlers.set(key, new Set())
      handlers.get(key)!.add(handler)
      return () => handlers.get(key)?.delete(handler)
    },
  }
}

describe("consoleApi", () => {
  it("maps dev login responses into auth sessions", async () => {
    const bridge = createMockBridge({
      "auth:dev.login": { accessToken: "token-123", username: "alice" },
    })
    const api = createConsoleApi(bridge)

    await expect(api.login("alice")).resolves.toEqual({
      accessToken: "token-123",
      username: "alice",
    })
  })

  it("maps session statuses from the gateway list contract", async () => {
    const bridge = createMockBridge({
      "/api/me/sessions": [
        {
          sessionId: "session-1",
          workerId: "worker-1",
          status: "DetachedGracePeriod",
          createdAt: "2026-04-21T00:00:00Z",
          lastActivityAt: "2026-04-21T00:01:00Z",
        },
      ],
    })
    const api = createConsoleApi(bridge)

    await expect(api.listSessions()).resolves.toEqual([
      {
        sessionId: "session-1",
        workerId: "worker-1",
        status: "detached",
        createdAt: "2026-04-21T00:00:00Z",
        lastActivityAt: "2026-04-21T00:01:00Z",
      },
    ])
  })

  it("maps session detail responses from the gateway contract", async () => {
    const bridge = createMockBridge({
      "/api/me/sessions/session-1": {
        sessionId: "session-1",
        workerId: "worker-1",
        status: "Attached",
        createdAt: "2026-04-21T00:00:00Z",
        lastActivityAt: "2026-04-21T00:01:00Z",
      },
    })
    const api = createConsoleApi(bridge)

    await expect(api.getSession("session-1")).resolves.toEqual({
      sessionId: "session-1",
      workerId: "worker-1",
      status: "live",
      createdAt: "2026-04-21T00:00:00Z",
      lastActivityAt: "2026-04-21T00:01:00Z",
    })
  })

  it("maps worker responses into the console worker shape", async () => {
    const bridge = createMockBridge({
      "/api/me/workers": [
        {
          workerId: "worker-1",
          name: "Worker One",
          isOnline: true,
          sessionCount: 2,
          lastSeenAtUtc: "2026-04-21T00:02:00Z",
        },
      ],
    })
    const api = createConsoleApi(bridge)

    await expect(api.listWorkers()).resolves.toEqual([
      {
        workerId: "worker-1",
        name: "Worker One",
        isOnline: true,
        sessionCount: 2,
        lastSeenAt: "2026-04-21T00:02:00Z",
      },
    ])
  })

  it("maps worker detail responses and hosted session statuses", async () => {
    const bridge = createMockBridge({
      "/api/me/workers/worker-1": {
        workerId: "worker-1",
        name: "Worker One",
        isOnline: true,
        sessionCount: 2,
        lastSeenAtUtc: "2026-04-21T00:02:00Z",
        sessions: [
          {
            sessionId: "session-1",
            workerId: "worker-1",
            status: "Exited",
            createdAt: "2026-04-21T00:00:00Z",
            lastActivityAt: "2026-04-21T00:01:00Z",
          },
        ],
      },
    })
    const api = createConsoleApi(bridge)

    await expect(api.getWorker("worker-1")).resolves.toEqual({
      workerId: "worker-1",
      name: "Worker One",
      isOnline: true,
      sessionCount: 2,
      lastSeenAt: "2026-04-21T00:02:00Z",
      sessions: [
        {
          sessionId: "session-1",
          workerId: "worker-1",
          status: "exited",
          createdAt: "2026-04-21T00:00:00Z",
          lastActivityAt: "2026-04-21T00:01:00Z",
        },
      ],
    })
  })
})
