/**
 * @file ArtifactsTransport.ets
 * @brief SignalR HubConnection for receiving ArtifactChanged events.
 *
 * Gateway pushes ArtifactChanged to all of the user's connections
 * (web Console, HarmonyOS, multi-device). Local-only updates keep
 * the feed state fresh without refetching.
 */
import { HubConnectionBuilder, HubConnection, HubConnectionState, LogLevel } from '@rwecho/signalr'
import { ArtifactModel, mapArtifactModel } from '../model/ArtifactModels'

export type ArtifactChangeHandler = (
  sessionId: string,
  artifactId: string,
  changeType: string,
  artifact: ArtifactModel | null,
) => void

export class ArtifactsTransport {
  private connection: HubConnection | null = null
  private onChange: ArtifactChangeHandler | null = null

  setOnChange(handler: ArtifactChangeHandler): void {
    this.onChange = handler
  }

  async connect(token: string, gatewayUrl: string): Promise<void> {
    if (this.connection && this.connection.state === HubConnectionState.Connected) {
      return
    }
    if (!token || token.trim().length === 0) {
      throw new Error('Missing gateway access token')
    }

    const baseUrl = gatewayUrl.replace(/\/+$/, '')
    const hubUrl = baseUrl + '/hubs/terminal'

    this.connection = new HubConnectionBuilder()
      .withUrl(hubUrl)
      .withAccessToken(() => token)
      .withAutomaticReconnect([0, 2000, 5000, 10000, 30000])
      .configureLogging(LogLevel.Information)
      .build()

    const conn = this.connection

    conn.on('ArtifactChanged', (args: Object[]) => {
      this.handleArtifactChanged(args[0])
    })

    await conn.start()
  }

  async disconnect(): Promise<void> {
    if (!this.connection) {
      return
    }
    const conn = this.connection
    this.connection = null
    await conn.stop()
  }

  private handleArtifactChanged(payload: Object): void {
    const record = payload as Record<string, Object>
    const sessionId = (record['sessionId'] as string) ?? ''
    const artifactId = (record['artifactId'] as string) ?? ''
    const changeType = (record['changeType'] as string) ?? ''
    const artifactPayload = record['artifact']
    const artifact = artifactPayload
      ? mapArtifactModel(artifactPayload as Record<string, Object>)
      : null
    if (this.onChange) {
      this.onChange(sessionId, artifactId, changeType, artifact)
    }
  }
}
