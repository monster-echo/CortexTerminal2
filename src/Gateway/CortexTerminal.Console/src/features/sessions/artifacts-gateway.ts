import {
  HubConnection,
  HubConnectionBuilder,
  HttpTransportType,
  LogLevel,
} from '@microsoft/signalr'
import type { ArtifactChangedEvent } from '@/services/console-api'

export interface ArtifactGatewayHandlers {
  onArtifactChanged(event: ArtifactChangedEvent): void
}

export interface ArtifactGateway {
  start(handlers: ArtifactGatewayHandlers): Promise<void>
  stop(): Promise<void>
}

export function createArtifactGateway(deps: {
  hubUrl?: string
  accessTokenFactory?: () => string | null
} = {}): ArtifactGateway {
  const { hubUrl = '/hubs/terminal', accessTokenFactory = () => null } = deps
  let connection: HubConnection | null = null
  let currentHandlers: ArtifactGatewayHandlers | null = null

  return {
    async start(handlers) {
      currentHandlers = handlers
      if (connection) return
      connection = new HubConnectionBuilder()
        .withUrl(hubUrl, {
          accessTokenFactory: () => accessTokenFactory() ?? '',
          transport: HttpTransportType.WebSockets | HttpTransportType.LongPolling,
        })
        .withAutomaticReconnect()
        .configureLogging(LogLevel.Error)
        .build()

      connection.on('ArtifactChanged', (event: ArtifactChangedEvent) => {
        currentHandlers?.onArtifactChanged(event)
      })

      await connection.start()
    },
    async stop() {
      const conn = connection
      connection = null
      currentHandlers = null
      if (conn) {
        try { await conn.stop() } catch { /* ignored on shutdown */ }
      }
    },
  }
}
