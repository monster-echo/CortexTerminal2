import { describe, expect, it } from "vitest"
import { resolveConsoleRoute, toConsoleHash } from "./consoleApp"

describe("consoleApp", () => {
  it("routes anonymous users to the login page", () => {
    expect(resolveConsoleRoute("#/sessions/session-1", false)).toEqual({
      kind: "login",
      path: "/login",
    })
  })

  it("defaults authenticated users to the session list", () => {
    expect(resolveConsoleRoute("", true)).toEqual({
      kind: "session-list",
      path: "/sessions",
    })
    expect(resolveConsoleRoute("#/login", true)).toEqual({
      kind: "session-list",
      path: "/sessions",
    })
  })

  it("routes authenticated users to a session detail page", () => {
    expect(resolveConsoleRoute("#/sessions/session-1", true)).toEqual({
      kind: "session-detail",
      path: "/sessions/session-1",
      sessionId: "session-1",
    })
  })

  it("routes authenticated users to worker pages", () => {
    expect(resolveConsoleRoute("#/workers", true)).toEqual({
      kind: "worker-list",
      path: "/workers",
    })
    expect(resolveConsoleRoute("#/workers/worker-9", true)).toEqual({
      kind: "worker-detail",
      path: "/workers/worker-9",
      workerId: "worker-9",
    })
  })

  it("formats hashes for navigation", () => {
    expect(toConsoleHash("/workers/worker-9")).toBe("#/workers/worker-9")
  })
})
