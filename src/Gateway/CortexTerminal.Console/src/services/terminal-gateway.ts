import {
  HubConnectionBuilder,
  HttpTransportType,
  LogLevel,
  type HubConnection,
} from '@microsoft/signalr'

export interface TerminalGatewayHandlers {
  onStdout(payload: Uint8Array): void
  onStderr(payload: Uint8Array): void
  onSessionReattached(sessionId: string): void
  onReplayChunk(payload: Uint8Array, stream: 'stdout' | 'stderr'): void
  onReplayCompleted(): void
  onSessionExpired(reason?: string): void
}

export interface TerminalGatewayConnection {
  writeInput(payload: Uint8Array): Promise<void>
  resize(columns: number, rows: number): Promise<void>
  probeLatency(probeId: string): Promise<void>
  close(): Promise<void>
  dispose(): Promise<void>
}

export interface TerminalGateway {
  connect(
    sessionId: string,
    handlers: TerminalGatewayHandlers
  ): Promise<TerminalGatewayConnection>
}

type TerminalChunkDto = {
  sessionId?: string
  stream?: string
  payload?: Uint8Array | number[] | string
}

type SessionIdDto = {
  sessionId?: string
}

type SessionExpiredDto = SessionIdDto & {
  reason?: string
}

type SessionCommandResult = {
  isSuccess: boolean
  errorCode?: string | null
}

type LatencyProbeDto = {
  sessionId?: string
  probeId?: string
}

type PendingLatencyProbe = {
  resolve: () => void
  reject: (error: Error) => void
  timeoutId: ReturnType<typeof globalThis.setTimeout>
}

export function createTerminalGateway(
  deps: {
    hubUrl?: string
    accessTokenFactory?: () => string | null
  } = {}
): TerminalGateway {
  const { hubUrl = '/hubs/terminal', accessTokenFactory = () => null } = deps

  return {
    async connect(sessionId, handlers) {
      const pendingProbes = new Map<string, PendingLatencyProbe>()
      const connection = new HubConnectionBuilder()
        .withUrl(hubUrl, {
          accessTokenFactory: () => accessTokenFactory() ?? '',
          transport:
            HttpTransportType.WebSockets | HttpTransportType.LongPolling,
        })
        .withAutomaticReconnect()
        .configureLogging(LogLevel.Error)
        .build()

      const rejectPendingProbes = (reason: string) => {
        for (const [probeId, probe] of pendingProbes) {
          globalThis.clearTimeout(probe.timeoutId)
          probe.reject(new Error(reason))
          pendingProbes.delete(probeId)
        }
      }

      registerTerminalHandlers(connection, sessionId, handlers, (probe) => {
        if (!probe.probeId) {
          return
        }

        const pendingProbe = pendingProbes.get(probe.probeId)
        if (!pendingProbe) {
          return
        }

        globalThis.clearTimeout(pendingProbe.timeoutId)
        pendingProbes.delete(probe.probeId)
        pendingProbe.resolve()
      })

      connection.onclose(() => {
        rejectPendingProbes('Terminal connection closed.')
      })

      connection.onreconnecting(() => {
        rejectPendingProbes('Terminal connection is reconnecting.')
      })

      // Re-attach session after SignalR automatic reconnect (e.g. app resumes from background)
      connection.onreconnected(async () => {
        try {
          const reattachResult = (await connection.invoke('ReattachSession', {
            sessionId,
          })) as SessionCommandResult

          if (!reattachResult.isSuccess) {
            if (
              reattachResult.errorCode === 'session-expired' ||
              reattachResult.errorCode === 'session-not-found'
            ) {
              handlers.onSessionExpired(reattachResult.errorCode)
              await connection.stop()
            }
          }
        } catch {
          // Reattach failed — connection will be disposed by the UI layer
        }
      })

      await connection.start()

      const result = (await connection.invoke('ReattachSession', {
        sessionId,
      })) as SessionCommandResult

      if (!result.isSuccess) {
        if (
          result.errorCode === 'session-expired' ||
          result.errorCode === 'session-not-found'
        ) {
          handlers.onSessionExpired(result.errorCode)
          await connection.stop()
          return disconnectedConnection()
        }

        await connection.stop()
        throw new Error(result.errorCode ?? 'Could not connect terminal.')
      }

      return {
        writeInput(payload) {
          return connection.invoke('WriteInput', {
            sessionId,
            payload: encodeSignalRBytes(payload),
          })
        },
        resize(columns, rows) {
          return connection.invoke('ResizeSession', {
            sessionId,
            columns,
            rows,
          })
        },
        probeLatency(probeId) {
          return new Promise<void>((resolve, reject) => {
            const timeoutId = globalThis.setTimeout(() => {
              pendingProbes.delete(probeId)
              reject(new Error('Latency probe timed out.'))
            }, 5000)

            pendingProbes.set(probeId, {
              resolve,
              reject,
              timeoutId,
            })

            connection
              .invoke('ProbeLatency', {
                sessionId,
                probeId,
              })
              .catch((error: unknown) => {
                const pendingProbe = pendingProbes.get(probeId)
                if (!pendingProbe) {
                  return
                }

                globalThis.clearTimeout(pendingProbe.timeoutId)
                pendingProbes.delete(probeId)
                pendingProbe.reject(
                  error instanceof Error
                    ? error
                    : new Error('Latency probe failed.')
                )
              })
          })
        },
        close() {
          return connection.invoke('CloseSession', { sessionId })
        },
        dispose() {
          rejectPendingProbes('Terminal connection disposed.')
          return connection.stop()
        },
      }
    },
  }
}

function registerTerminalHandlers(
  connection: HubConnection,
  sessionId: string,
  handlers: TerminalGatewayHandlers,
  onLatencyProbeAck: (probe: LatencyProbeDto) => void
) {
  connection.on('StdoutChunk', (chunk: TerminalChunkDto) => {
    if (chunk.sessionId === sessionId) {
      handlers.onStdout(decodeSignalRBytes(chunk.payload))
    }
  })
  connection.on('StderrChunk', (chunk: TerminalChunkDto) => {
    if (chunk.sessionId === sessionId) {
      handlers.onStderr(decodeSignalRBytes(chunk.payload))
    }
  })
  connection.on('SessionReattached', (evt: SessionIdDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionReattached(sessionId)
    }
  })
  connection.on('ReplayChunk', (chunk: TerminalChunkDto) => {
    if (
      chunk.sessionId === sessionId &&
      (chunk.stream === 'stdout' || chunk.stream === 'stderr')
    ) {
      handlers.onReplayChunk(decodeSignalRBytes(chunk.payload), chunk.stream)
    }
  })
  connection.on('ReplayCompleted', (evt: SessionIdDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onReplayCompleted()
    }
  })
  connection.on('SessionExpired', (evt: SessionExpiredDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionExpired(evt.reason)
    }
  })
  connection.on('SessionExited', (evt: SessionExpiredDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionExpired(evt.reason)
    }
  })
  connection.on('SessionStartFailed', (evt: SessionExpiredDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionExpired(evt.reason)
    }
  })
  connection.on('LatencyProbeAck', (probe: LatencyProbeDto) => {
    if (probe.sessionId === sessionId) {
      onLatencyProbeAck(probe)
    }
  })
}

function disconnectedConnection(): TerminalGatewayConnection {
  return {
    writeInput: async () => undefined,
    resize: async () => undefined,
    probeLatency: async () => undefined,
    close: async () => undefined,
    dispose: async () => undefined,
  }
}

export function decodeSignalRBytes(
  payload: Uint8Array | number[] | string | undefined
) {
  if (payload instanceof Uint8Array) {
    return payload
  }

  if (typeof payload === 'string') {
    return Uint8Array.from(
      Array.from(atob(payload), (character) => character.charCodeAt(0))
    )
  }

  return new Uint8Array(payload ?? [])
}

export function encodeSignalRBytes(payload: Uint8Array) {
  return btoa(String.fromCharCode(...payload))
}
