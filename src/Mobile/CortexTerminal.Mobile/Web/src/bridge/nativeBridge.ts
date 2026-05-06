import type { BridgeResponse, BridgeEvent, NativeBridge } from "./types"
import { BridgeError } from "./types"

function encodeBinary(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
}

function decodeBinary(base64: string): Uint8Array {
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
}

export function createNativeBridge(): NativeBridge {
  const pending = new Map<
    string,
    { resolve: (value: unknown) => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> }
  >()
  const eventHandlers = new Map<string, Set<(payload: unknown, binary?: Uint8Array) => void>>()

  function eventKey(channel: string, method: string) {
    return `${channel}:${method}`
  }

  function handleNativeMessage(raw: string) {
    let msg: BridgeResponse | BridgeEvent
    try {
      msg = JSON.parse(raw)
    } catch {
      console.error("[Bridge] Failed to parse native message:", raw)
      return
    }

    if (msg.type === "response") {
      const entry = pending.get(msg.id)
      if (entry) {
        pending.delete(msg.id)
        clearTimeout(entry.timer)
        if (msg.ok) {
          entry.resolve(msg.payload)
        } else {
          entry.reject(new BridgeError(msg.error ?? "Unknown error", msg.errorCode))
        }
      }
    } else if (msg.type === "event") {
      const evt = msg as BridgeEvent
      const key = eventKey(evt.channel, evt.method)
      const binary = evt.binaryPayload ? decodeBinary(evt.binaryPayload) : undefined
      const handlers = eventHandlers.get(key)
      if (handlers) {
        for (const handler of handlers) {
          try {
            handler(evt.payload, binary)
          } catch (err) {
            console.error(`[Bridge] Event handler error for ${key}:`, err)
          }
        }
      }
    }
  }

  // Receive C# → JS messages via HybridWebViewMessageReceived event (SendRawMessage pattern)
  window.addEventListener("HybridWebViewMessageReceived", ((event: Event) => {
    const raw = (event as CustomEvent).detail?.message
    if (typeof raw === "string") {
      handleNativeMessage(raw)
    }
  }) as EventListener)

  return {
    async request<T>(channel: string, method: string, payload?: unknown, binaryPayload?: Uint8Array): Promise<T> {
      const id = crypto.randomUUID()

      return new Promise<T>((resolve, reject) => {
        const timer = setTimeout(() => {
          if (pending.delete(id)) {
            reject(new BridgeError("Bridge request timed out", "timeout"))
          }
        }, 30_000)

        pending.set(id, {
          resolve: resolve as (v: unknown) => void,
          reject,
          timer,
        })

        const message = JSON.stringify({
          id,
          type: "request",
          channel,
          method,
          payload,
          binaryPayload: binaryPayload ? encodeBinary(binaryPayload) : undefined,
        })

        if (window.HybridWebView?.SendRawMessage) {
          window.HybridWebView.SendRawMessage(message)
        } else {
          // Dev fallback: log to console when not running in MAUI
          pending.delete(id)
          clearTimeout(timer)
          reject(new BridgeError("HybridWebView not available", "no-webview"))
        }
      })
    },

    onEvent(channel, method, handler) {
      const key = eventKey(channel, method)
      let set = eventHandlers.get(key)
      if (!set) {
        set = new Set()
        eventHandlers.set(key, set)
      }
      set.add(handler)
      return () => {
        set!.delete(handler)
        if (set!.size === 0) {
          eventHandlers.delete(key)
        }
      }
    },
  }
}
