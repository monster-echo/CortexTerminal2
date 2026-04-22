import { act, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { TerminalView } from "./TerminalView"
import type { TerminalGateway, TerminalGatewayConnection, TerminalGatewayHandlers } from "../services/terminalGateway"

describe("TerminalView", () => {
  it("resets session state and disposes the old connection when the session changes", async () => {
    const handlersBySession = new Map<string, TerminalGatewayHandlers>()
    const sessionOneConnection = createConnection()
    const sessionTwoConnection = createConnection()
    const gateway = createGateway(async (sessionId, handlers) => {
      handlersBySession.set(sessionId, handlers)
      return sessionId === "session-1" ? sessionOneConnection : sessionTwoConnection
    })

    const view = render(<TerminalView gateway={gateway} sessionId="session-1" />)

    await waitFor(() => expect(gateway.connect).toHaveBeenCalledWith("session-1", expect.any(Object)))

    await act(async () => {
      handlersBySession.get("session-1")?.onSessionExpired("process-exited")
    })

    expect(screen.getByTestId("terminal-status").textContent).toBe("expired")
    expect(screen.getByRole("alert").textContent).toContain("process-exited")

    view.rerender(<TerminalView gateway={gateway} sessionId="session-2" />)

    await waitFor(() => expect(gateway.connect).toHaveBeenCalledWith("session-2", expect.any(Object)))
    await act(async () => {
      handlersBySession.get("session-2")?.onSessionReattached("session-2")
    })

    expect(sessionOneConnection.dispose).toHaveBeenCalledOnce()
    expect(screen.getByTestId("terminal-status").textContent).toBe("reattached")
  })
})

function createGateway(
  connectImpl: (sessionId: string, handlers: TerminalGatewayHandlers) => Promise<TerminalGatewayConnection>
): TerminalGateway {
  return {
    connect: vi.fn(connectImpl),
  }
}

function createConnection(): TerminalGatewayConnection {
  return {
    writeInput: vi.fn().mockResolvedValue(undefined),
    resize: vi.fn().mockResolvedValue(undefined),
    close: vi.fn().mockResolvedValue(undefined),
    dispose: vi.fn().mockResolvedValue(undefined),
  }
}
