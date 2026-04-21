import {
  HubConnectionBuilder,
  HttpTransportType,
  LogLevel,
  type HubConnection,
} from "@microsoft/signalr"

export interface TerminalGatewayHandlers {
  onStdout(payload: Uint8Array): void
  onStderr(payload: Uint8Array): void
  onSessionReattached(sessionId: string): void
  onReplayChunk(payload: Uint8Array, stream: "stdout" | "stderr"): void
  onReplayCompleted(): void
  onSessionExpired(reason?: string): void
}

export interface TerminalGatewayConnection {
  writeInput(payload: Uint8Array): Promise<void>
  resize(columns: number, rows: number): Promise<void>
  close(): Promise<void>
  dispose(): Promise<void>
}

export interface TerminalGateway {
  connect(sessionId: string, handlers: TerminalGatewayHandlers): Promise<TerminalGatewayConnection>
}

type TerminalChunkDto = {
  sessionId?: string
  stream?: string
  payload?: Uint8Array | number[]
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

export function createTerminalGateway(deps: {
  hubUrl?: string
  accessTokenFactory?: () => string | null
} = {}): TerminalGateway {
  const { hubUrl = "/hubs/terminal", accessTokenFactory = () => null } = deps

  return {
    async connect(sessionId, handlers) {
      const connection = new HubConnectionBuilder()
        .withUrl(hubUrl, {
          accessTokenFactory: () => accessTokenFactory() ?? "",
          transport: HttpTransportType.WebSockets | HttpTransportType.LongPolling,
        })
        .withAutomaticReconnect()
        .configureLogging(LogLevel.Error)
        .build()

      registerTerminalHandlers(connection, sessionId, handlers)
      await connection.start()

      const result = (await connection.invoke("ReattachSession", {
        sessionId,
      })) as SessionCommandResult

      if (!result.isSuccess) {
        if (result.errorCode === "session-expired" || result.errorCode === "session-not-found") {
          handlers.onSessionExpired(result.errorCode)
          await connection.stop()
          return disconnectedConnection()
        }

        await connection.stop()
        throw new Error(result.errorCode ?? "Could not connect terminal.")
      }

      return {
        writeInput(payload) {
          return connection.invoke("WriteInput", { sessionId, payload })
        },
        resize(columns, rows) {
          return connection.invoke("ResizeSession", { sessionId, columns, rows })
        },
        close() {
          return connection.invoke("CloseSession", { sessionId })
        },
        dispose() {
          return connection.stop()
        },
      }
    },
  }
}

function registerTerminalHandlers(
  connection: HubConnection,
  sessionId: string,
  handlers: TerminalGatewayHandlers
) {
  connection.on("StdoutChunk", (chunk: TerminalChunkDto) => {
    if (chunk.sessionId === sessionId) {
      handlers.onStdout(toUint8Array(chunk.payload))
    }
  })
  connection.on("StderrChunk", (chunk: TerminalChunkDto) => {
    if (chunk.sessionId === sessionId) {
      handlers.onStderr(toUint8Array(chunk.payload))
    }
  })
  connection.on("SessionReattached", (evt: SessionIdDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionReattached(sessionId)
    }
  })
  connection.on("ReplayChunk", (chunk: TerminalChunkDto) => {
    if (chunk.sessionId === sessionId && (chunk.stream === "stdout" || chunk.stream === "stderr")) {
      handlers.onReplayChunk(toUint8Array(chunk.payload), chunk.stream)
    }
  })
  connection.on("ReplayCompleted", (evt: SessionIdDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onReplayCompleted()
    }
  })
  connection.on("SessionExpired", (evt: SessionExpiredDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionExpired(evt.reason)
    }
  })
  connection.on("SessionExited", (evt: SessionExpiredDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionExpired(evt.reason)
    }
  })
  connection.on("SessionStartFailed", (evt: SessionExpiredDto) => {
    if (evt.sessionId === sessionId) {
      handlers.onSessionExpired(evt.reason)
    }
  })
}

function toUint8Array(payload: Uint8Array | number[] | undefined) {
  if (payload instanceof Uint8Array) {
    return payload
  }

  return new Uint8Array(payload ?? [])
}

function disconnectedConnection(): TerminalGatewayConnection {
  return {
    writeInput: async () => undefined,
    resize: async () => undefined,
    close: async () => undefined,
    dispose: async () => undefined,
  }
}
