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

describe("Session API operations via bridge", () => {
  it("creates a session with shell runtime and default dimensions", async () => {
    const requests: Array<{ channel: string; method: string; payload?: unknown }> = []
    const bridge: NativeBridge = {
      async request<T>(channel: string, method: string, payload?: unknown): Promise<T> {
        requests.push({ channel, method, payload })
        return { sessionId: "session-2", workerId: "worker-1" } as T
      },
      onEvent: () => () => {},
    }
    const api = createConsoleApi(bridge)

    const result = await api.createSession()

    expect(result.sessionId).toBe("session-2")
    expect(requests).toContainEqual(
      expect.objectContaining({
        channel: "rest",
        method: "*",
        payload: expect.objectContaining({
          method: "POST",
          path: "/api/sessions",
          body: { runtime: "shell", columns: 120, rows: 40 },
        }),
      }),
    )
  })

  it("deletes a session via the REST bridge", async () => {
    const requests: Array<{ channel: string; method: string; payload?: unknown }> = []
    const bridge: NativeBridge = {
      async request<T>(channel: string, method: string, payload?: unknown): Promise<T> {
        requests.push({ channel, method, payload })
        return undefined as unknown as T
      },
      onEvent: () => () => {},
    }
    const api = createConsoleApi(bridge)

    await api.deleteSession("session-1")

    expect(requests).toContainEqual(
      expect.objectContaining({
        channel: "rest",
        method: "*",
        payload: expect.objectContaining({
          method: "DELETE",
          path: "/api/me/sessions/session-1",
        }),
      }),
    )
  })

  it("lists sessions with mapped statuses", async () => {
    const bridge = createMockBridge({
      "/api/me/sessions": [
        { sessionId: "s1", workerId: "w1", status: "Attached", createdAt: "", lastActivityAt: "" },
        { sessionId: "s2", workerId: "w1", status: "Exited", createdAt: "", lastActivityAt: "" },
      ],
    })
    const api = createConsoleApi(bridge)

    const sessions = await api.listSessions()

    expect(sessions[0]!.status).toBe("live")
    expect(sessions[1]!.status).toBe("exited")
  })
})
