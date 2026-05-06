import { describe, expect, it } from "vitest"
import { createConsoleApi } from "../services/consoleApi"
import type { NativeBridge } from "../bridge/types"

function createMockBridge(responses: Record<string, unknown> = {}): NativeBridge {
  return {
    async request<T>(channel: string, method: string, payload?: unknown): Promise<T> {
      if (channel === "rest" && method === "*") {
        const path = (payload as { path?: string })?.path ?? ""
        const resp = responses[path]
        if (resp !== undefined) return resp as T
        return [] as unknown as T
      }
      const key = `${channel}:${method}`
      const resp = responses[key]
      if (resp !== undefined) return resp as T
      return undefined as unknown as T
    },
    onEvent: () => () => {},
  }
}

describe("Worker API operations via bridge", () => {
  it("lists workers with name and status mapping", async () => {
    const bridge = createMockBridge({
      "/api/me/workers": [
        {
          workerId: "worker-1",
          name: "Alpha",
          isOnline: true,
          sessionCount: 2,
          lastSeenAtUtc: "2026-04-21T00:02:00Z",
        },
      ],
    })
    const api = createConsoleApi(bridge)

    const workers = await api.listWorkers()

    expect(workers).toEqual([
      {
        workerId: "worker-1",
        name: "Alpha",
        isOnline: true,
        sessionCount: 2,
        lastSeenAt: "2026-04-21T00:02:00Z",
      },
    ])
  })

  it("gets worker detail with hosted sessions", async () => {
    const bridge = createMockBridge({
      "/api/me/workers/worker-1": {
        workerId: "worker-1",
        name: "Alpha",
        isOnline: true,
        sessionCount: 2,
        lastSeenAtUtc: "2026-04-21T00:02:00Z",
        sessions: [
          {
            sessionId: "session-1",
            workerId: "worker-1",
            status: "Attached",
            createdAt: "2026-04-21T00:00:00Z",
            lastActivityAt: "2026-04-21T00:01:00Z",
          },
        ],
      },
    })
    const api = createConsoleApi(bridge)

    const worker = await api.getWorker("worker-1")

    expect(worker.name).toBe("Alpha")
    expect(worker.sessions).toEqual([
      expect.objectContaining({
        sessionId: "session-1",
        status: "live",
      }),
    ])
  })

  it("sends upgrade request via the REST bridge", async () => {
    const requests: Array<{ channel: string; method: string; payload?: unknown }> = []
    const bridge: NativeBridge = {
      async request<T>(channel: string, method: string, payload?: unknown): Promise<T> {
        requests.push({ channel, method, payload })
        return undefined as unknown as T
      },
      onEvent: () => () => {},
    }
    const api = createConsoleApi(bridge)

    await api.upgradeWorker("worker-1")

    expect(requests).toContainEqual(
      expect.objectContaining({
        channel: "rest",
        method: "*",
        payload: expect.objectContaining({
          method: "POST",
          path: "/api/me/workers/worker-1/upgrade",
        }),
      }),
    )
  })
})
