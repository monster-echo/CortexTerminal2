export type TerminalSessionState =
  | "live"
  | "reattached"
  | "replaying"
  | "expired";

export function createTerminalSessionModel(deps: {
  writeInput: (payload: Uint8Array) => void;
  onStateChange?: (state: TerminalSessionState) => void;
  onStream?: (chunk: { stream: "stdout" | "stderr"; text: string }) => void;
}) {
  let state: TerminalSessionState = "live";
  const transitionTo = (
    next: TerminalSessionState,
    allowedFrom: TerminalSessionState[],
  ) => {
    if (state === next || !allowedFrom.includes(state)) {
      return;
    }

    state = next;
    deps.onStateChange?.(state);
  };
  const emitStream = (stream: "stdout" | "stderr", payload: Uint8Array) => {
    const text = new TextDecoder().decode(payload);
    deps.onStream?.({ stream, text });
    return text;
  };

  return {
    getState() {
      return state;
    },
    onTerminalData(data: string) {
      deps.writeInput(new TextEncoder().encode(data));
    },
    onStdout(payload: Uint8Array) {
      return emitStream("stdout", payload);
    },
    onStderr(payload: Uint8Array) {
      return emitStream("stderr", payload);
    },
    onSessionReattached(sessionId: string) {
      transitionTo("reattached", ["live"]);
      return sessionId;
    },
    onReplayChunk(payload: Uint8Array, stream: "stdout" | "stderr") {
      transitionTo("replaying", ["reattached"]);
      emitStream(stream, payload);
      return { payload, stream };
    },
    onReplayCompleted() {
      transitionTo("live", ["reattached", "replaying"]);
    },
    onSessionExpired() {
      transitionTo("expired", ["live", "reattached", "replaying"]);
    },
  };
}

export function useTerminalSession(writeInput: (payload: Uint8Array) => void) {
  return createTerminalSessionModel({ writeInput });
}
