import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { WorkerDetailPage } from "./WorkerDetailPage"
import { WorkerListPage } from "./WorkerListPage"
import type { ConsoleApi, WorkerDetail, WorkerSummary } from "../services/consoleApi"

function createApi(overrides: Partial<ConsoleApi> = {}): ConsoleApi {
  return {
    login: vi.fn(),
    listSessions: vi.fn(),
    getSession: vi.fn(),
    createSession: vi.fn(),
    listWorkers: vi.fn().mockResolvedValue([] satisfies WorkerSummary[]),
    getWorker: vi.fn(),
    ...overrides,
  }
}

describe("Worker pages", () => {
  it("renders the current user's workers", async () => {
    const api = createApi({
      listWorkers: vi.fn().mockResolvedValue([
        {
          workerId: "worker-1",
          displayName: "Alpha",
          isOnline: true,
          sessionCount: 2,
          lastSeenAt: "2026-04-21T00:02:00Z",
        },
      ] satisfies WorkerSummary[]),
    })

    render(<WorkerListPage api={api} navigate={vi.fn()} />)

    expect(await screen.findByText("Alpha")).toBeTruthy()
    expect(screen.getByText("2 sessions")).toBeTruthy()
  })

  it("shows a worker summary and hosted sessions", async () => {
    const navigate = vi.fn()
    const api = createApi({
      getWorker: vi.fn().mockResolvedValue({
        workerId: "worker-1",
        displayName: "Alpha",
        isOnline: true,
        sessionCount: 2,
        lastSeenAt: "2026-04-21T00:02:00Z",
        sessions: [
          {
            sessionId: "session-1",
            workerId: "worker-1",
            status: "live",
            createdAt: "2026-04-21T00:00:00Z",
            lastActivityAt: "2026-04-21T00:01:00Z",
          },
        ],
      } satisfies WorkerDetail),
    })

    render(<WorkerDetailPage api={api} workerId="worker-1" navigate={navigate} />)

    expect(await screen.findByText("Worker Alpha")).toBeTruthy()
    expect(screen.getByText("Hosted sessions")).toBeTruthy()
    expect(screen.getByText("session-1")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Open session" }))
    expect(navigate).toHaveBeenCalledWith("/sessions/session-1")
  })

  it("clears stale detail content while loading a different worker", async () => {
    let resolveSecondRequest!: (value: WorkerDetail) => void
    const api = createApi({
      getWorker: vi
        .fn()
        .mockResolvedValueOnce({
          workerId: "worker-1",
          displayName: "Alpha",
          isOnline: true,
          sessionCount: 2,
          lastSeenAt: "2026-04-21T00:02:00Z",
          sessions: [],
        } satisfies WorkerDetail)
        .mockImplementationOnce(
          () =>
            new Promise<WorkerDetail>((resolve) => {
              resolveSecondRequest = resolve
            })
        ),
    })

    const view = render(<WorkerDetailPage api={api} workerId="worker-1" navigate={vi.fn()} />)

    expect(await screen.findByText("Worker Alpha")).toBeTruthy()

    view.rerender(<WorkerDetailPage api={api} workerId="worker-2" navigate={vi.fn()} />)

    expect(screen.queryByText("Worker Alpha")).toBeNull()
    expect(screen.getByText("Loading worker…")).toBeTruthy()

    if (typeof resolveSecondRequest !== "function") {
      throw new Error("expected pending detail request")
    }

    resolveSecondRequest({
      workerId: "worker-2",
      displayName: "Beta",
      isOnline: false,
      sessionCount: 1,
      lastSeenAt: "2026-04-21T00:05:00Z",
      sessions: [],
    })

    expect(await screen.findByText("Worker Beta")).toBeTruthy()
  })
})
