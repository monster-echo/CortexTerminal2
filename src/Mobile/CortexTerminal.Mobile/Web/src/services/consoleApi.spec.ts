import { describe, expect, it, vi } from "vitest"
import { createConsoleApi } from "./consoleApi"

describe("consoleApi", () => {
  it("maps dev login responses into auth sessions", async () => {
    const fetchFn = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ accessToken: "token-123" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    )
    const api = createConsoleApi({ fetchFn })

    await expect(api.login("alice")).resolves.toEqual({
      token: "token-123",
      username: "alice",
    })
  })

  it("does not clear auth state when a login request is unauthorized", async () => {
    const onUnauthorized = vi.fn()
    const api = createConsoleApi({
      fetchFn: vi.fn().mockResolvedValue(new Response(null, { status: 401 })),
      onUnauthorized,
    })

    await expect(api.login("alice")).rejects.toThrow("Login failed.")
    expect(onUnauthorized).not.toHaveBeenCalled()
  })

  it("surfaces access denied errors for forbidden requests", async () => {
    const api = createConsoleApi({
      fetchFn: vi.fn().mockResolvedValue(new Response(null, { status: 403 })),
      getToken: () => "token-123",
    })

    await expect(api.getSession("session-1")).rejects.toThrow("Access denied.")
  })

  it("maps session statuses from the gateway list contract", async () => {
    const fetchFn = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify([
          {
            sessionId: "session-1",
            workerId: "worker-1",
            status: "DetachedGracePeriod",
            createdAt: "2026-04-21T00:00:00Z",
            lastActivityAt: "2026-04-21T00:01:00Z",
          },
        ]),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }
      )
    )
    const api = createConsoleApi({ fetchFn, getToken: () => "token-123" })

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
    const fetchFn = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          sessionId: "session-1",
          workerId: "worker-1",
          status: "Attached",
          createdAt: "2026-04-21T00:00:00Z",
          lastActivityAt: "2026-04-21T00:01:00Z",
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }
      )
    )
    const api = createConsoleApi({ fetchFn, getToken: () => "token-123" })

    await expect(api.getSession("session-1")).resolves.toEqual({
      sessionId: "session-1",
      workerId: "worker-1",
      status: "live",
      createdAt: "2026-04-21T00:00:00Z",
      lastActivityAt: "2026-04-21T00:01:00Z",
    })
  })

  it("sends the default shell session payload when creating a session", async () => {
    const fetchFn = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ sessionId: "session-1", workerId: "worker-1" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    )
    const api = createConsoleApi({ fetchFn, getToken: () => "token-123" })

    await api.createSession()

    expect(fetchFn).toHaveBeenCalledWith(
      "/api/sessions",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ runtime: "shell", columns: 120, rows: 40 }),
        headers: expect.any(Headers),
      })
    )
  })

  it("maps worker responses into the console worker shape", async () => {
    const fetchFn = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify([
          {
            workerId: "worker-1",
            name: "Worker One",
            isOnline: true,
            sessionCount: 2,
            lastSeenAtUtc: "2026-04-21T00:02:00Z",
          },
        ]),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }
      )
    )
    const api = createConsoleApi({ fetchFn, getToken: () => "token-123" })

    await expect(api.listWorkers()).resolves.toEqual([
      {
        workerId: "worker-1",
        displayName: "Worker One",
        isOnline: true,
        sessionCount: 2,
        lastSeenAt: "2026-04-21T00:02:00Z",
      },
    ])
  })

  it("maps worker detail responses and hosted session statuses", async () => {
    const fetchFn = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
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
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }
      )
    )
    const api = createConsoleApi({ fetchFn, getToken: () => "token-123" })

    await expect(api.getWorker("worker-1")).resolves.toEqual({
      workerId: "worker-1",
      displayName: "Worker One",
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
