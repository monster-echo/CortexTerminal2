import { render, screen, waitFor } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { App } from "./App"

const authStorageKey = "gateway-console-auth"

describe("App", () => {
  beforeEach(() => {
    window.localStorage.clear()
    window.location.hash = ""
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("routes anonymous users to login even when a protected hash is requested", () => {
    window.location.hash = "#/sessions/session-1"

    render(<App />)

    expect(screen.getByRole("heading", { name: "Sign in" })).toBeTruthy()
  })

  it("uses stored auth to open hash-routed pages", async () => {
    window.localStorage.setItem(
      authStorageKey,
      JSON.stringify({
        token: "token-123",
        username: "alice",
      })
    )
    window.location.hash = "#/workers"
    vi.spyOn(window, "fetch").mockResolvedValue(
      new Response(JSON.stringify([]), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    )

    render(<App />)

    await waitFor(() => expect(screen.getByRole("heading", { name: "Workers" })).toBeTruthy())
    expect(screen.getByText("Signed in as alice")).toBeTruthy()
  })

  it("clears expired auth and returns to login on unauthorized responses", async () => {
    window.localStorage.setItem(
      authStorageKey,
      JSON.stringify({
        token: "token-123",
        username: "alice",
      })
    )
    window.location.hash = "#/workers"
    vi.spyOn(window, "fetch").mockResolvedValue(new Response(null, { status: 401 }))

    render(<App />)

    await waitFor(() => expect(screen.getByRole("heading", { name: "Sign in" })).toBeTruthy())
    expect(window.localStorage.getItem(authStorageKey)).toBeNull()
  })

  it("renders the console shell classes", () => {
    render(<App />)

    expect(document.querySelector(".min-h-screen")).not.toBeNull()
  })
})
