import type { NativeBridge } from "../bridge/types"

export interface TerminalGatewayHandlers {
  onStdout(payload: Uint8Array): void
  onStderr(payload: Uint8Array): void
  onSessionReattached(sessionId: string): void
  onReplayChunk(payload: Uint8Array, stream: "stdout" | "stderr"): void
  onReplayCompleted(): void
  onSessionExpired(reason?: string): void
  onLatencyProbeAck?(probeId: string): void
}

export interface TerminalGatewayConnection {
  writeInput(payload: Uint8Array): Promise<void>
  resize(columns: number, rows: number): Promise<void>
  probeLatency(probeId: string): Promise<void>
  close(): Promise<void>
  dispose(): Promise<void>
}

export interface TerminalGateway {
  connect(sessionId: string, handlers: TerminalGatewayHandlers): Promise<TerminalGatewayConnection>
}

type EventPayload = Record<string, unknown>

export function createTerminalGateway(bridge: NativeBridge): TerminalGateway {
  return {
    async connect(sessionId, handlers) {
      const unsubs: (() => void)[] = []

      unsubs.push(
        bridge.onEvent("signalr", "StdoutChunk", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            handlers.onStdout(decodePayload(payload.payload as string | undefined))
          }
        }),
      )

      unsubs.push(
        bridge.onEvent("signalr", "StderrChunk", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            handlers.onStderr(decodePayload(payload.payload as string | undefined))
          }
        }),
      )

      unsubs.push(
        bridge.onEvent("signalr", "SessionReattached", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            handlers.onSessionReattached(sessionId)
          }
        }),
      )

      unsubs.push(
        bridge.onEvent("signalr", "ReplayChunk", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            const stream = payload.stream === "stderr" ? "stderr" : "stdout"
            handlers.onReplayChunk(decodePayload(payload.payload as string | undefined), stream)
          }
        }),
      )

      unsubs.push(
        bridge.onEvent("signalr", "ReplayCompleted", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            handlers.onReplayCompleted()
          }
        }),
      )

      unsubs.push(
        bridge.onEvent("signalr", "SessionExpired", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            handlers.onSessionExpired(payload.reason as string | undefined)
          }
        }),
      )

      unsubs.push(
        bridge.onEvent("signalr", "SessionExited", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            handlers.onSessionExpired(payload.reason as string | undefined)
          }
        }),
      )

      unsubs.push(
        bridge.onEvent("signalr", "SessionStartFailed", (raw) => {
          const payload = raw as EventPayload | null
          if (payload?.sessionId === sessionId) {
            handlers.onSessionExpired(payload.reason as string | undefined)
          }
        }),
      )

      if (handlers.onLatencyProbeAck) {
        unsubs.push(
          bridge.onEvent("signalr", "LatencyProbeAck", (raw) => {
            const payload = raw as EventPayload | null
            if (payload?.sessionId === sessionId && payload.probeId) {
              handlers.onLatencyProbeAck!(payload.probeId as string)
            }
          }),
        )
      }

      const result = await bridge.request<{
        isSuccess: boolean
        errorCode?: string
      }>("signalr", "connect", { sessionId })

      if (!result.isSuccess) {
        unsubs.forEach((fn) => fn())
        if (
          result.errorCode === "session-expired" ||
          result.errorCode === "session-not-found"
        ) {
          handlers.onSessionExpired(result.errorCode)
          return disconnectedConnection(unsubs)
        }
        throw new Error(result.errorCode ?? "Could not connect terminal.")
      }

      return {
        writeInput(payload) {
          return bridge.request("signalr", "WriteInput", {
            sessionId,
            payload: encodePayload(payload),
          })
        },
        resize(columns, rows) {
          return bridge.request("signalr", "ResizeSession", {
            sessionId,
            columns,
            rows,
          })
        },
        probeLatency(probeId) {
          return bridge.request("signalr", "ProbeLatency", {
            sessionId,
            probeId,
          })
        },
        close() {
          return bridge.request("signalr", "CloseSession", { sessionId })
        },
        async dispose() {
          unsubs.forEach((fn) => fn())
        },
      }
    },
  }
}

function decodePayload(base64: string | undefined): Uint8Array {
  if (!base64) return new Uint8Array(0)
  return Uint8Array.from(
    Array.from(atob(base64), (c) => c.charCodeAt(0)),
  )
}

function encodePayload(payload: Uint8Array): string {
  return btoa(String.fromCharCode(...payload))
}

function disconnectedConnection(
  unsubs: (() => void)[],
): TerminalGatewayConnection {
  return {
    writeInput: async () => undefined,
    resize: async () => undefined,
    probeLatency: async () => undefined,
    close: async () => undefined,
    async dispose() {
      unsubs.forEach((fn) => fn())
    },
  }
}
