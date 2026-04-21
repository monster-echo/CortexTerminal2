export type TerminalSessionState = "live" | "reattached" | "replaying" | "expired"

export function createTerminalSessionModel(deps: {
  writeInput: (payload: Uint8Array) => void
  onStateChange?: (state: TerminalSessionState) => void
}) {
  let state: TerminalSessionState = "live"

  return {
    onTerminalData(data: string) {
      deps.writeInput(new TextEncoder().encode(data))
    },
    onStdout(payload: Uint8Array) {
      return new TextDecoder().decode(payload)
    },
    onStderr(payload: Uint8Array) {
      return new TextDecoder().decode(payload)
    },
    onSessionReattached(sessionId: string) {
      state = "reattached"
      deps.onStateChange?.(state)
      return sessionId
    },
    onReplayChunk(payload: Uint8Array, stream: "stdout" | "stderr") {
      state = "replaying"
      deps.onStateChange?.(state)
      return { payload, stream }
    },
    onReplayCompleted() {
      state = "live"
      deps.onStateChange?.(state)
    },
    onSessionExpired() {
      state = "expired"
      deps.onStateChange?.(state)
    },
  }
}

export function useTerminalSession(writeInput: (payload: Uint8Array) => void) {
  return createTerminalSessionModel({ writeInput })
}
