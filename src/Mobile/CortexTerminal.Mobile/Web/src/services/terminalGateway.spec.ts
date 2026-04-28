import { describe, expect, it } from "vitest"
import { decodeSignalRBytes, encodeSignalRBytes } from "./terminalGateway"

describe("terminalGateway byte conversion", () => {
  it("encodes terminal input as base64 for SignalR JSON transport", () => {
    const payload = new TextEncoder().encode("echo hello\n")

    expect(encodeSignalRBytes(payload)).toBe("ZWNobyBoZWxsbwo=")
  })

  it("decodes base64 terminal output from SignalR JSON transport", () => {
    const payload = "aGVsbG8K"

    expect(new TextDecoder().decode(decodeSignalRBytes(payload))).toBe("hello\n")
  })
})
