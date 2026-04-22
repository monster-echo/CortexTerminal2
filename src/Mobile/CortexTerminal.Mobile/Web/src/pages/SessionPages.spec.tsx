import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { SessionDetailPage } from "./SessionDetailPage"
import { SessionListPage } from "./SessionListPage"
import type { ConsoleApi, SessionDetail, SessionSummary, WorkerDetail, WorkerSummary } from "../services/consoleApi"
import type { TerminalGateway } from "../services/terminalGateway"

function createApi(overrides: Partial<ConsoleApi> = {}): ConsoleApi {
  return {
    login: vi.fn(),
    listSessions: vi.fn().mockResolvedValue([] satisfies SessionSummary[]),
    getSession: vi.fn(),
    createSession: vi.fn(),
    listWorkers: vi.fn().mockResolvedValue([] satisfies WorkerSummary[]),
    getWorker: vi.fn().mockResolvedValue({} as WorkerDetail),
    ...overrides,
  }
}

function createTerminalGateway(overrides: Partial<TerminalGateway> = {}): TerminalGateway {
  return {
    connect: vi.fn().mockResolvedValue({
      writeInput: vi.fn(),
      resize: vi.fn(),
      close: vi.fn(),
      dispose: vi.fn(),
    }),
    ...overrides,
  }
}

describe("Session pages", () => {
  it("renders sessions and opens a newly created session", async () => {
    const api = createApi({
      listSessions: vi.fn().mockResolvedValue([
        {
          sessionId: "session-1",
          workerId: "worker-1",
          status: "live",
          createdAt: "2026-04-21T00:00:00Z",
          lastActivityAt: "2026-04-21T00:01:00Z",
        },
      ] satisfies SessionSummary[]),
      createSession: vi.fn().mockResolvedValue({ sessionId: "session-2" }),
    })
    const navigate = vi.fn()

    render(<SessionListPage api={api} navigate={navigate} />)

    expect(await screen.findByText("session-1")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Start session" }))

    await waitFor(() => expect(api.createSession).toHaveBeenCalled())
    expect(navigate).toHaveBeenCalledWith("/sessions/session-2")
  })

  it("shows a create error without hiding the loaded session list", async () => {
    const api = createApi({
      listSessions: vi.fn().mockResolvedValue([
        {
          sessionId: "session-1",
          workerId: "worker-1",
          status: "live",
          createdAt: "2026-04-21T00:00:00Z",
          lastActivityAt: "2026-04-21T00:01:00Z",
        },
      ] satisfies SessionSummary[]),
      createSession: vi.fn().mockRejectedValue(new Error("Session start failed")),
    })

    render(<SessionListPage api={api} navigate={vi.fn()} />)

    expect(await screen.findByText("session-1")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Start session" }))

    expect((await screen.findByRole("status")).textContent).toContain("Session start failed")
    expect(screen.getByText("session-1")).toBeTruthy()
  })

  it("clears stale detail content while loading a different session", async () => {
    let resolveSecondRequest!: (value: SessionDetail) => void
    const api = createApi({
      getSession: vi
        .fn()
        .mockResolvedValueOnce({
          sessionId: "session-1",
          workerId: "worker-1",
          status: "detached",
          createdAt: "2026-04-21T00:00:00Z",
          lastActivityAt: "2026-04-21T00:01:00Z",
        } satisfies SessionDetail)
        .mockImplementationOnce(
          () =>
            new Promise<SessionDetail>((resolve) => {
              resolveSecondRequest = resolve
            })
        ),
    })

    const view = render(
      <SessionDetailPage
        api={api}
        sessionId="session-1"
        navigate={vi.fn()}
        terminalGateway={createTerminalGateway()}
      />
    )

    expect(await screen.findByText("Session session-1")).toBeTruthy()

    view.rerender(
      <SessionDetailPage
        api={api}
        sessionId="session-2"
        navigate={vi.fn()}
        terminalGateway={createTerminalGateway()}
      />
    )

    expect(screen.queryByText("Session session-1")).toBeNull()
    expect(screen.getByText("Loading session…")).toBeTruthy()

    if (typeof resolveSecondRequest !== "function") {
      throw new Error("expected pending detail request")
    }

    resolveSecondRequest({
      sessionId: "session-2",
      workerId: "worker-2",
      status: "live",
      createdAt: "2026-04-21T00:02:00Z",
      lastActivityAt: "2026-04-21T00:03:00Z",
    })

    expect(await screen.findByText("Session session-2")).toBeTruthy()
  })

  it("connects the terminal gateway for the loaded session and renders live output", async () => {
    const writeInput = vi.fn()
    let handlers: Record<string, ((...args: unknown[]) => void) | undefined> = {}
    const terminalGateway = createTerminalGateway({
      connect: vi.fn().mockImplementation(
        async (_sessionId: string, nextHandlers: Record<string, (...args: unknown[]) => void>) => {
          handlers = nextHandlers
          return {
            writeInput,
            resize: vi.fn(),
            close: vi.fn(),
            dispose: vi.fn(),
          }
        }
      ),
    })
    const api = createApi({
      getSession: vi.fn().mockResolvedValue({
        sessionId: "session-1",
        workerId: "worker-1",
        status: "live",
        createdAt: "2026-04-21T00:00:00Z",
        lastActivityAt: "2026-04-21T00:01:00Z",
      } satisfies SessionDetail),
    })

    render(<SessionDetailPage api={api} sessionId="session-1" navigate={vi.fn()} terminalGateway={terminalGateway} />)

    expect(await screen.findByText("Session session-1")).toBeTruthy()
    await waitFor(() => expect(terminalGateway.connect).toHaveBeenCalledWith("session-1", expect.any(Object)))

    await act(async () => {
      handlers.onStdout?.(new Uint8Array([0x48, 0x69]))
    })

    expect(screen.getByTestId("terminal-output").textContent).toContain("Hi")
    fireEvent.click(screen.getByRole("button", { name: "send-tab" }))
    expect(writeInput).toHaveBeenCalledOnce()
  })

  it("shows terminal expiry details from gateway events", async () => {
    const terminalGateway = createTerminalGateway({
      connect: vi.fn().mockImplementation(async (_sessionId, handlers) => {
        handlers.onSessionExpired("process-exited")
        return {
          writeInput: vi.fn(),
          resize: vi.fn(),
          close: vi.fn(),
          dispose: vi.fn(),
        }
      }),
    })
    const api = createApi({
      getSession: vi.fn().mockResolvedValue({
        sessionId: "session-1",
        workerId: "worker-1",
        status: "live",
        createdAt: "2026-04-21T00:00:00Z",
        lastActivityAt: "2026-04-21T00:01:00Z",
      } satisfies SessionDetail),
    })

    render(<SessionDetailPage api={api} sessionId="session-1" navigate={vi.fn()} terminalGateway={terminalGateway} />)

    expect(await screen.findByText("Session session-1")).toBeTruthy()
    await waitFor(() => expect(screen.getByTestId("terminal-status").textContent).toBe("expired"))
    expect(screen.getByRole("alert").textContent).toContain("process-exited")
  })
})
