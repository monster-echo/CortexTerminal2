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

  it("reports decoded stdout and stderr text through a stream callback", () => {
    const onStream = vi.fn()
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStream,
    } as never)

    session.onStdout(new Uint8Array([0x48, 0x69]))
    session.onStderr(new Uint8Array([0x6f, 0x68]))

    expect(onStream).toHaveBeenNthCalledWith(1, { stream: "stdout", text: "Hi" })
    expect(onStream).toHaveBeenNthCalledWith(2, { stream: "stderr", text: "oh" })
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

  it("emits replaying only once for repeated replay chunks", () => {
    const states: string[] = []
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStateChange: (state) => states.push(state),
    })

    session.onSessionReattached("session-123")
    session.onReplayChunk(new Uint8Array([0x61]), "stdout")
    session.onReplayChunk(new Uint8Array([0x62]), "stderr")

    expect(states).toEqual(["reattached", "replaying"])
  })

  it("reports decoded replay chunks while preserving reattach state transitions", () => {
    const states: string[] = []
    const onStream = vi.fn()
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStateChange: (state: string) => states.push(state),
      onStream,
    } as never)

    session.onSessionReattached("session-123")
    session.onReplayChunk(new Uint8Array([0x6f, 0x6b]), "stdout")
    session.onReplayCompleted()

    expect(onStream).toHaveBeenCalledWith({ stream: "stdout", text: "ok" })
    expect(states).toEqual(["reattached", "replaying", "live"])
  })

  it("ignores session reattached events while already replaying", () => {
    const states: string[] = []
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStateChange: (state) => states.push(state),
    })

    session.onSessionReattached("session-123")
    session.onReplayChunk(new Uint8Array([0x61]), "stdout")
    const sessionId = session.onSessionReattached("session-456")

    expect(sessionId).toBe("session-456")
    expect(states).toEqual(["reattached", "replaying"])
  })

  it("does not leave expired when replay completion arrives late", () => {
    const states: string[] = []
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStateChange: (state) => states.push(state),
    })

    session.onSessionReattached("session-123")
    session.onReplayChunk(new Uint8Array([0x61]), "stdout")
    session.onSessionExpired()
    session.onReplayCompleted()

    expect(states).toEqual(["reattached", "replaying", "expired"])
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
