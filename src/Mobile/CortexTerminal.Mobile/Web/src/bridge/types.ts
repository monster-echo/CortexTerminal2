export interface BridgeMessage {
  id: string
  type: "request"
  channel: string
  method: string
  payload?: unknown
  binaryPayload?: string
}

export interface BridgeResponse {
  id: string
  type: "response"
  ok: boolean
  payload?: unknown
  error?: string
  errorCode?: string
}

export interface BridgeEvent {
  id: string
  type: "event"
  channel: string
  method: string
  payload?: unknown
  binaryPayload?: string
}

export interface NativeBridge {
  request<T>(channel: string, method: string, payload?: unknown, binaryPayload?: Uint8Array): Promise<T>
  onEvent(channel: string, method: string, handler: (payload: unknown, binaryPayload?: Uint8Array) => void): () => void
}

export class BridgeError extends Error {
  readonly errorCode?: string
  constructor(message: string, errorCode?: string) {
    super(message)
    this.name = "BridgeError"
    this.errorCode = errorCode
  }
}

declare global {
  interface Window {
    HybridWebView?: {
      SendRawMessage: (message: string) => void
      InvokeDotNet: (methodName: string, paramValues?: unknown[]) => Promise<unknown>
      __InvokeJavaScript: (taskId: string, methodName: (...args: unknown[]) => unknown, args: unknown[]) => Promise<void>
    }
  }
}
