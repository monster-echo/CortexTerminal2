export type TerminalSessionState = "live" | "reattached" | "replaying" | "expired"

export function createTerminalSessionModel(deps: {
  writeInput: (payload: Uint8Array) => void
  onStateChange?: (state: TerminalSessionState) => void
}) {
  let state: TerminalSessionState = "live"
  const transitionTo = (next: TerminalSessionState, allowedFrom: TerminalSessionState[]) => {
    if (state === next || !allowedFrom.includes(state)) {
      return
    }

    state = next
    deps.onStateChange?.(state)
  }

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
      transitionTo("reattached", ["live"])
      return sessionId
    },
    onReplayChunk(payload: Uint8Array, stream: "stdout" | "stderr") {
      transitionTo("replaying", ["reattached"])
      return { payload, stream }
    },
    onReplayCompleted() {
      transitionTo("live", ["reattached", "replaying"])
    },
    onSessionExpired() {
      transitionTo("expired", ["live", "reattached", "replaying"])
    },
  }
}

export function useTerminalSession(writeInput: (payload: Uint8Array) => void) {
  return createTerminalSessionModel({ writeInput })
}
