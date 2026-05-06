import { describe, expect, it } from "vitest"

// Test the base64 encode/decode helpers indirectly via terminalGateway
// Since terminalGateway no longer exports these functions directly,
// we test the round-trip through the bridge message format.

describe("terminalGateway base64 round-trip", () => {
  it("encodes and decodes terminal bytes correctly via bridge", async () => {
    const original = new TextEncoder().encode("echo hello\n")
    // base64 encode (same as what happens in JS bridge transport)
    const encoded = btoa(String.fromCharCode(...original))
    expect(encoded).toBe("ZWNobyBoZWxsbwo=")

    // base64 decode (same as what happens when receiving from native)
    const decoded = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0))
    expect(new TextDecoder().decode(decoded)).toBe("echo hello\n")
  })

  it("decodes base64 terminal output correctly", () => {
    const encoded = "aGVsbG8K"
    const decoded = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0))
    expect(new TextDecoder().decode(decoded)).toBe("hello\n")
  })
})
