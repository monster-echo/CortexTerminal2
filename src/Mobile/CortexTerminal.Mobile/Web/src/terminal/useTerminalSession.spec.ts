import { describe, it, expect, vi } from "vitest"
import { useTerminalSession } from "./useTerminalSession"

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
})
