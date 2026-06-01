import { buffer } from '@kit.ArkTS'
import { HubConnectionBuilder, HubConnection, HubConnectionState, LogLevel } from '@rwecho/signalr'
import {
  TransportFrame,
  ReattachSessionParams,
  WriteInputParams,
  ResizeSessionParams,
  CloseSessionParams,
  ProbeLatencyParams,
} from '../model/TerminalTransportModels'

type OnFrameCallback = (frame: TransportFrame) => void
type OnDisconnectedCallback = () => void

export class TerminalTransport {
  isConnected: boolean = false

  onFrame: OnFrameCallback | null = null
  onDisconnected: OnDisconnectedCallback | null = null

  private connection: HubConnection | null = null
  private sessionId: string = ''
  private latencyProbeTimer: number = -1
  private manualDisconnect: boolean = false
  private pendingProbes: Map<string, number> = new Map()

  async connect(sessionId: string, token: string, gatewayUrl: string): Promise<void> {
    if (!sessionId || sessionId.trim().length === 0) {
      throw new Error('Missing terminal session id')
    }
    if (!token || token.trim().length === 0) {
      throw new Error('Missing gateway access token')
    }

    this.sessionId = sessionId
    this.manualDisconnect = false
    this.stopLatencyProbe()

    const baseUrl = gatewayUrl.replace(/\/+$/, '')
    const hubUrl = baseUrl + '/hubs/terminal'
    console.info(`[TerminalTransport] connecting to ${hubUrl}, sessionId=${sessionId}, token=${token.substring(0, 10)}...`)

    this.connection = new HubConnectionBuilder()
      .withUrl(hubUrl)
      .withAccessToken(() => token)
      .withAutomaticReconnect([0, 2000, 5000, 10000, 30000])
      .configureLogging(LogLevel.Information)
      .build()

    const conn = this.connection

    conn.on('SessionReattached', (args: Object[]) => {
      const frame = new TransportFrame()
      frame.type = 'replaying'
      frame.sessionId = this.sessionId
      this.emitFrame(frame)
    })

    conn.on('ReplayChunk', (args: Object[]) => {
      const chunk = args[0] as Record<string, Object>
      const frame = new TransportFrame()
      frame.type = 'replay'
      frame.sessionId = (chunk['sessionId'] as string) ?? this.sessionId
      frame.stream = (chunk['stream'] as string) ?? 'stdout'
      frame.payload = this.payloadToBase64(chunk['payload'])
      this.emitFrame(frame)
    })

    conn.on('ReplayCompleted', (args: Object[]) => {
      const replayFrame = new TransportFrame()
      replayFrame.type = 'replayCompleted'
      replayFrame.sessionId = this.sessionId
      this.emitFrame(replayFrame)

      const liveFrame = new TransportFrame()
      liveFrame.type = 'live'
      liveFrame.sessionId = this.sessionId
      this.emitFrame(liveFrame)
    })

    conn.on('StdoutChunk', (args: Object[]) => {
      const chunk = args[0] as Record<string, Object>
      const frame = new TransportFrame()
      frame.type = 'output'
      frame.sessionId = (chunk['sessionId'] as string) ?? this.sessionId
      frame.stream = (chunk['stream'] as string) ?? 'stdout'
      frame.payload = this.payloadToBase64(chunk['payload'])
      console.info(`[Transport] StdoutChunk: payload=${frame.payload.substring(0, 60)}`)
      this.emitFrame(frame)
    })

    conn.on('StderrChunk', (args: Object[]) => {
      const chunk = args[0] as Record<string, Object>
      const frame = new TransportFrame()
      frame.type = 'output'
      frame.sessionId = (chunk['sessionId'] as string) ?? this.sessionId
      frame.stream = (chunk['stream'] as string) ?? 'stderr'
      frame.payload = this.payloadToBase64(chunk['payload'])
      console.info(`[Transport] StderrChunk: payload=${frame.payload.substring(0, 60)}`)
      this.emitFrame(frame)
    })

    conn.on('SessionDetached', (args: Object[]) => {
      const evt = args[0] as Record<string, Object>
      const frame = new TransportFrame()
      frame.type = 'detached'
      frame.sessionId = (evt['sessionId'] as string) ?? this.sessionId
      this.emitFrame(frame)
    })

    conn.on('SessionExpired', (args: Object[]) => {
      const evt = args[0] as Record<string, Object>
      const frame = new TransportFrame()
      frame.type = 'expired'
      frame.sessionId = (evt['sessionId'] as string) ?? this.sessionId
      frame.reason = (evt['reason'] as string) ?? 'worker-offline'
      this.emitFrame(frame)
    })

    conn.on('SessionExited', (args: Object[]) => {
      const evt = args[0] as Record<string, Object>
      const frame = new TransportFrame()
      frame.type = 'exited'
      frame.sessionId = (evt['sessionId'] as string) ?? this.sessionId
      frame.exitCode = (evt['exitCode'] as number) ?? 0
      frame.reason = (evt['reason'] as string) ?? ''
      this.emitFrame(frame)
    })

    conn.on('SessionStartFailed', (args: Object[]) => {
      const evt = args[0] as Record<string, Object>
      const frame = new TransportFrame()
      frame.type = 'error'
      frame.sessionId = (evt['sessionId'] as string) ?? this.sessionId
      frame.code = 'session-start-failed'
      frame.message = (evt['reason'] as string) ?? 'Session start failed'
      this.emitFrame(frame)
    })

    conn.on('LatencyProbeAck', (args: Object[]) => {
      const ackData = args[0] as Record<string, Object>
      const probeId = (ackData['probeId'] as string) ?? ''
      const sendTime = this.pendingProbes.get(probeId)
      if (sendTime !== undefined) {
        this.pendingProbes.delete(probeId)
        const rtt = Date.now() - sendTime
        console.info(`[LatencyProbeAck] probeId=${probeId}, rtt=${rtt}ms`)
        const frame = new TransportFrame()
        frame.type = 'latencyAck'
        frame.probeId = probeId
        frame.clientTime = rtt
        frame.serverTime = 0
        this.emitFrame(frame)
      }
    })

    conn.onreconnecting = (_error: Error | null) => {
      this.isConnected = false
      this.stopLatencyProbe()
      if (!this.manualDisconnect && this.onDisconnected) {
        this.onDisconnected()
      }
    }

    conn.onreconnected = (_connectionId: string | null) => {
      this.isConnected = true
      this.startLatencyProbe()
      this.reattachSession()
    }

    conn.onclose = (_error: Error | null) => {
      this.isConnected = false
      this.stopLatencyProbe()
    }

    await conn.start()
    this.isConnected = true
    console.info(`[TerminalTransport] HubConnection started, invoking ReattachSession`)

    await this.reattachSession()
    this.startLatencyProbe()
  }

  sendInput(base64Payload: string): void {
    if (!this.connection || this.connection.state !== HubConnectionState.Connected) {
      console.warn('[Transport] sendInput skipped: not connected')
      return
    }
    console.info(`[Transport] sendInput: base64=${base64Payload}`)
    const params = new WriteInputParams()
    params.sessionId = this.sessionId
    params.payload = base64Payload
    this.connection.send('WriteInput', params).then(() => {
      console.info('[Transport] WriteInput sent OK')
    }).catch((e: Error) => {
      console.error('[Transport] WriteInput failed: ' + e.message)
    })
  }

  sendResize(columns: number, rows: number): void {
    if (!this.connection || this.connection.state !== HubConnectionState.Connected) {
      return
    }
    const params = new ResizeSessionParams()
    params.sessionId = this.sessionId
    params.columns = columns
    params.rows = rows
    this.connection.send('ResizeSession', params).catch((e: Error) => {
      console.error('Failed to send resize: ' + e.message)
    })
  }

  sendDetach(): void {
    this.manualDisconnect = true
    if (this.connection && this.connection.state === HubConnectionState.Connected) {
      this.connection.invoke('DetachSession', this.sessionId).catch((_e: Error) => {
        // Ignore detach errors
      })
    }
    setTimeout(() => {
      this.disconnect()
    }, 100)
  }

  sendClose(): void {
    if (this.connection && this.connection.state === HubConnectionState.Connected) {
      const params = new CloseSessionParams()
      params.sessionId = this.sessionId
      this.connection.send('CloseSession', params).catch((_e: Error) => {
        // Ignore close errors
      })
    }
  }

  disconnect(): void {
    this.manualDisconnect = true
    this.stopLatencyProbe()
    if (this.connection) {
      this.connection.stop().catch((_e: Error) => {
        // Ignore stop errors
      })
      this.connection = null
    }
    this.isConnected = false
  }

  private async reattachSession(): Promise<void> {
    if (!this.connection || this.connection.state !== HubConnectionState.Connected) {
      return
    }
    try {
      const params = new ReattachSessionParams()
      params.sessionId = this.sessionId
      const result = await this.connection.invoke('ReattachSession', params)
      if (result !== null) {
        const r = result as Record<string, Object>
        const success = r['isSuccess'] ?? r['IsSuccess']
        if (success === false || success === 0) {
          const errorCode = (r['errorCode'] as string) ?? (r['ErrorCode'] as string) ?? 'unknown'
          this.emitReattachError(errorCode)
          this.disconnect()
          return
        }
      }
    } catch (e) {
      this.emitReattachError('reattach-failed: ' + (e as Error).message)
      this.disconnect()
    }
  }

  private emitReattachError(errorCode: string): void {
    const frame = new TransportFrame()
    frame.type = 'error'
    frame.sessionId = this.sessionId
    frame.code = errorCode
    frame.message = this.translateErrorCode(errorCode)
    this.emitFrame(frame)
  }

  private translateErrorCode(code: string): string {
    switch (code) {
      case 'session-not-found':
        return '会话不存在或无权访问'
      case 'session-expired':
        return '会话已过期，请创建新会话'
      case 'session-detached-without-lease':
        return '会话状态异常，请重试'
      default:
        return code
    }
  }

  private emitFrame(frame: TransportFrame): void {
    if (this.onFrame) {
      this.onFrame(frame)
    }
  }

  private startLatencyProbe(): void {
    this.stopLatencyProbe()
    this.pendingProbes.clear()
    this.latencyProbeTimer = setInterval(() => {
      if (!this.connection || this.connection.state !== HubConnectionState.Connected) {
        return
      }
      // Clean up probes older than 5 seconds
      const now = Date.now()
      const staleKeys: string[] = []
      this.pendingProbes.forEach((time, key) => {
        if (now - time > 5000) {
          staleKeys.push(key)
        }
      })
      for (const key of staleKeys) {
        this.pendingProbes.delete(key)
      }
      const probeId = `probe-${now}-${Math.floor(Math.random() * 100000)}`
      this.pendingProbes.set(probeId, now)
      console.info(`[LatencyProbe] sending probeId=${probeId}, pending=${this.pendingProbes.size}`)
      const params = new ProbeLatencyParams()
      params.sessionId = this.sessionId
      params.probeId = probeId
      this.connection.send('ProbeLatency', params).catch((_e: Error) => {
        this.pendingProbes.delete(probeId)
      })
    }, 15000) as number
  }

  private stopLatencyProbe(): void {
    if (this.latencyProbeTimer !== -1) {
      clearInterval(this.latencyProbeTimer)
      this.latencyProbeTimer = -1
    }
    this.pendingProbes.clear()
  }

  private payloadToBase64(payload: Object): string {
    if (payload === null || payload === undefined) {
      return ''
    }
    if (typeof payload === 'string') {
      return payload
    }
    try {
      const bytes = payload as number[]
      const arr = new Uint8Array(bytes)
      return buffer.from(arr.buffer).toString('base64')
    } catch (_e) {
      return String(payload)
    }
  }

  private base64ToBytes(base64: string): number[] {
    const map = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    const result: number[] = []
    const clean = base64.replace(/=+$/, '')
    for (let i = 0; i < clean.length; i += 4) {
      const c0 = map.indexOf(clean.charAt(i))
      const c1 = map.indexOf(clean.charAt(i + 1))
      const c2 = i + 2 < clean.length ? map.indexOf(clean.charAt(i + 2)) : 0
      const c3 = i + 3 < clean.length ? map.indexOf(clean.charAt(i + 3)) : 0
      result.push((c0 << 2) | (c1 >> 4))
      if (i + 2 < clean.length && clean.charAt(i + 2) !== '=') {
        result.push(((c1 & 15) << 4) | (c2 >> 2))
      }
      if (i + 3 < clean.length && clean.charAt(i + 3) !== '=') {
        result.push(((c2 & 3) << 6) | c3)
      }
    }
    return result
  }
}
