import { act, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import { TerminalView } from "./TerminalView"
import type { TerminalGateway, TerminalGatewayConnection, TerminalGatewayHandlers } from "../services/terminalGateway"

// Mock xterm and createBrowserTerminal
const mockWrite = vi.fn()
const mockFit = vi.fn().mockReturnValue({ columns: 80, rows: 24 })
const mockDispose = vi.fn()

vi.mock("./createBrowserTerminal", () => ({
  createBrowserTerminal: vi.fn((_container: HTMLElement, onData: (data: string) => void) => {
    // Store onData callback for test access
    (globalThis as any).__xtermOnData = onData
    return {
      write: mockWrite,
      fit: mockFit,
      dispose: mockDispose,
    }
  }),
}))

describe("TerminalView", () => {
  beforeEach(() => {
    mockWrite.mockClear()
    mockFit.mockClear()
    mockDispose.mockClear()
    delete (globalThis as any).__xtermOnData
  })

  it("mounts an xterm instance and forwards streamed output", async () => {
    let handlers: TerminalGatewayHandlers | undefined
    const gateway = createGateway(async (_sessionId, nextHandlers) => {
      handlers = nextHandlers
      return createConnection()
    })

    render(<TerminalView gateway={gateway} sessionId="session-123" />)

    await waitFor(() => expect(gateway.connect).toHaveBeenCalled())

    await act(async () => {
      handlers?.onStdout(new Uint8Array([0x68, 0x65, 0x6c, 0x6c, 0x6f])) // "hello"
    })

    expect(mockWrite).toHaveBeenCalledWith("hello")
  })

  it("sends terminal input data through the connection", async () => {
    const writeInput = vi.fn()
    const gateway = createGateway(async () => ({
      ...createConnection(),
      writeInput,
    }))

    render(<TerminalView gateway={gateway} sessionId="session-123" />)

    await waitFor(() => expect(gateway.connect).toHaveBeenCalled())

    // Simulate user typing in xterm
    const onData = (globalThis as any).__xtermOnData
    if (onData) {
      await act(async () => {
        onData("ls\r")
      })
    }

    expect(writeInput).toHaveBeenCalled()
  })

  it("calls resize on the connection when terminal is fitted", async () => {
    const resize = vi.fn()
    const gateway = createGateway(async () => ({
      ...createConnection(),
      resize,
    }))

    render(<TerminalView gateway={gateway} sessionId="session-123" />)

    await waitFor(() => expect(gateway.connect).toHaveBeenCalled())
    await waitFor(() => expect(resize).toHaveBeenCalledWith(80, 24))
  })

  it("disposes the xterm instance when unmounting", async () => {
    const gateway = createGateway(async () => createConnection())

    const view = render(<TerminalView gateway={gateway} sessionId="session-123" />)

    await waitFor(() => expect(gateway.connect).toHaveBeenCalled())

    view.unmount()

    expect(mockDispose).toHaveBeenCalled()
  })

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
