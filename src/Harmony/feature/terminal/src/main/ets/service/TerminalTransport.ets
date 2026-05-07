/**
 * @file TerminalTransport.ets
 * @brief WebSocket client for terminal session communication
 *
 * Manages the WebSocket connection to the terminal gateway.
 * Handles connect, send, reconnect with exponential backoff,
 * and ping/keep-alive.
 */
import { webSocket } from '@kit.NetworkKit'
import { buffer } from '@kit.ArkTS'
import { WsFrame } from '../model/TerminalTransportModels'

/**
 * Callback type for received WebSocket frames.
 */
type OnFrameCallback = (frame: Record<string, Object>) => void

/**
 * Callback type for disconnection events.
 */
type OnDisconnectedCallback = () => void

/**
 * Terminal transport layer using WebSocket.
 * Connects to the gateway, sends input/resize/detach commands,
 * and receives output frames.
 */
export class TerminalTransport {
  isConnected: boolean = false

  // Callbacks
  onFrame: OnFrameCallback | null = null
  onDisconnected: OnDisconnectedCallback | null = null

  // Internal state
  private ws: webSocket.WebSocket | null = null
  private sessionId: string = ''
  private token: string = ''
  private gatewayUrl: string = ''
  private pingTimer: number = -1
  private reconnectTimer: number = -1
  private reconnectAttempts: number = 0
  private maxReconnectAttempts: number = 10
  private baseReconnectDelay: number = 1000
  private maxReconnectDelay: number = 30000

  /**
   * Connect to the terminal session WebSocket.
   * @param sessionId The terminal session ID
   * @param token Authentication token
   * @param gatewayUrl The gateway base URL
   */
  async connect(sessionId: string, token: string, gatewayUrl: string): Promise<void> {
    this.sessionId = sessionId
    this.token = token
    this.gatewayUrl = gatewayUrl

    // Convert http(s) URL to ws(s) URL
    const wsUrl = gatewayUrl
      .replace('https://', 'wss://')
      .replace('http://', 'ws://')

    const fullUrl = `${wsUrl}/ws/terminal?sessionId=${sessionId}&token=${token}`

    return new Promise<void>((resolve, reject) => {
      this.ws = webSocket.createWebSocket()

      this.ws.on('open', () => {
        this.isConnected = true
        this.reconnectAttempts = 0
        this.startPing()
        resolve()
      })

      this.ws.on('message', (err: Error, data: string | ArrayBuffer) => {
        if (err) {
          console.error('WebSocket message error: ' + err.message)
          return
        }
        this.handleMessage(data)
      })

      this.ws.on('close', () => {
        this.isConnected = false
        this.stopPing()
        if (this.onDisconnected) {
          this.onDisconnected()
        }
        // Auto-reconnect with exponential backoff
        this.scheduleReconnect()
      })

      this.ws.on('error', (err: Error) => {
        console.error('WebSocket error: ' + err.message)
        this.isConnected = false
        reject(err)
      })

      this.ws.connect(fullUrl)
    })
  }

  /**
   * Send terminal input to the server.
   * @param base64Payload Base64-encoded input data
   */
  sendInput(base64Payload: string): void {
    const frame = new WsFrame()
    frame.type = 'input'
    frame.sessionId = this.sessionId
    frame.payload = base64Payload
    this.sendFrame(frame)
  }

  /**
   * Send a terminal resize event.
   * @param columns New column count
   * @param rows New row count
   */
  sendResize(columns: number, rows: number): void {
    const frame = new WsFrame()
    frame.type = 'resize'
    frame.sessionId = this.sessionId
    frame.columns = columns
    frame.rows = rows
    this.sendFrame(frame)
  }

  /**
   * Send a detach command to gracefully detach from the session.
   */
  sendDetach(): void {
    const frame = new WsFrame()
    frame.type = 'detach'
    frame.sessionId = this.sessionId
    this.sendFrame(frame)
    this.disconnect()
  }

  /**
   * Send a close/exit command.
   */
  sendClose(): void {
    const frame = new WsFrame()
    frame.type = 'close'
    frame.sessionId = this.sessionId
    this.sendFrame(frame)
  }

  /**
   * Start sending periodic ping frames to keep the connection alive.
   */
  startPing(): void {
    this.stopPing()
    this.pingTimer = setInterval(() => {
      const frame = new WsFrame()
      frame.type = 'ping'
      this.sendFrame(frame)
    }, 30000) as number
  }

  /**
   * Stop the ping timer.
   */
  stopPing(): void {
    if (this.pingTimer !== -1) {
      clearInterval(this.pingTimer)
      this.pingTimer = -1
    }
  }

  /**
   * Disconnect the WebSocket and cancel any pending reconnect.
   */
  disconnect(): void {
    this.cancelReconnect()
    this.stopPing()
    if (this.ws) {
      try {
        this.ws.close()
      } catch (e) {
        // Ignore close errors
      }
      this.ws = null
    }
    this.isConnected = false
  }

  /**
   * Handle an incoming WebSocket message.
   */
  private handleMessage(data: string | ArrayBuffer): void {
    try {
      let jsonStr: string
      if (typeof data === 'string') {
        jsonStr = data
      } else {
        jsonStr = buffer.from(data).toString('utf-8')
      }

      const frame = JSON.parse(jsonStr) as Record<string, Object>
      if (this.onFrame) {
        this.onFrame(frame)
      }
    } catch (e) {
      console.warn('Failed to parse WebSocket frame: ' + (e as Error).message)
    }
  }

  /**
   * Send a WsFrame over the WebSocket.
   */
  private sendFrame(frame: WsFrame): void {
    if (!this.ws || !this.isConnected) {
      return
    }
    try {
      const obj: Record<string, Object> = {}
      obj['type'] = frame.type
      obj['sessionId'] = frame.sessionId
      if (frame.payload) {
        obj['payload'] = frame.payload
      }
      if (frame.columns > 0) {
        obj['columns'] = frame.columns as Object
      }
      if (frame.rows > 0) {
        obj['rows'] = frame.rows as Object
      }
      const jsonStr = JSON.stringify(obj)
      this.ws.send(jsonStr)
    } catch (e) {
      console.error('Failed to send WebSocket frame: ' + (e as Error).message)
    }
  }

  /**
   * Schedule a reconnection attempt with exponential backoff.
   */
  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.warn('Max reconnect attempts reached')
      return
    }

    this.cancelReconnect()
    const delay = Math.min(
      this.baseReconnectDelay * Math.pow(2, this.reconnectAttempts),
      this.maxReconnectDelay
    )
    // Add jitter (0-25% of delay)
    const jitter = delay * (Math.random() * 0.25)
    const totalDelay = delay + jitter

    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++
      console.info(`Reconnect attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts}`)
      this.connect(this.sessionId, this.token, this.gatewayUrl).catch((e: Error) => {
        console.warn('Reconnect failed: ' + e.message)
      })
    }, totalDelay) as number
  }

  /**
   * Cancel any pending reconnect timer.
   */
  private cancelReconnect(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
  }
}
