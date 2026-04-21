import { describe, it, expect, vi } from "vitest"
import { createTerminalSessionModel, useTerminalSession } from "./useTerminalSession"

describe("useTerminalSession", () => {
  it("forwards xterm input as raw bytes", () => {
    const writeInput = vi.fn()
    const session = useTerminalSession(writeInput)

    session.onTerminalData("\t")

    expect(writeInput).toHaveBeenCalledOnce()
    expect(Array.from(writeInput.mock.calls[0]![0] as Uint8Array)).toEqual([0x09])
  })

  it("encodes multi-byte characters correctly", () => {
    const writeInput = vi.fn()
    const session = useTerminalSession(writeInput)

    session.onTerminalData("ls\r")

    expect(writeInput).toHaveBeenCalledOnce()
    expect(Array.from(writeInput.mock.calls[0]![0] as Uint8Array)).toEqual(
      Array.from(new TextEncoder().encode("ls\r"))
    )
  })

  it("decodes stdout binary payload to string", () => {
    const session = useTerminalSession(vi.fn())

    const result = session.onStdout(new Uint8Array([0x48, 0x65, 0x6c, 0x6c, 0x6f]))

    expect(result).toBe("Hello")
  })

  it("decodes stderr binary payload to string", () => {
    const session = useTerminalSession(vi.fn())

    const result = session.onStderr(new Uint8Array([0x45, 0x72, 0x72]))

    expect(result).toBe("Err")
  })

  it("transitions from reattached to replaying to live", () => {
    const states: string[] = []
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStateChange: (state) => states.push(state),
    })
    const replayPayload = new Uint8Array([0x6f, 0x6b])

    const sessionId = session.onSessionReattached("session-123")
    const replayChunk = session.onReplayChunk(replayPayload, "stdout")
    session.onReplayCompleted()

    expect(sessionId).toBe("session-123")
    expect(replayChunk).toEqual({ payload: replayPayload, stream: "stdout" })
    expect(states).toEqual(["reattached", "replaying", "live"])
  })

  it("transitions to expired when the session expires", () => {
    const states: string[] = []
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStateChange: (state) => states.push(state),
    })

    session.onSessionExpired()

    expect(states).toEqual(["expired"])
  })
})
