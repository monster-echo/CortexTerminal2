/* eslint-disable @typescript-eslint/no-explicit-any */
import type { Transport } from "./types";

/**
 * Production transport using the MAUI HybridWebView bridge.
 */
export class HybridWebViewTransport implements Transport {
  private getHost() {
    return (window as any).HybridWebView;
  }

  async invoke(methodName: string, args: unknown[]): Promise<any> {
    const host = this.getHost();
    if (!host?.InvokeDotNet) {
      throw new Error("HybridWebView.InvokeDotNet is not available.");
    }
    return host.InvokeDotNet(methodName, args);
  }

  sendRaw(message: unknown): void {
    const host = this.getHost();
    if (host?.SendRawMessage) {
      host.SendRawMessage(JSON.stringify(message));
    }
  }

  onMessage(handler: (data: unknown) => void): () => void {
    const listener = (event: Event) => {
      const customEvent = event as CustomEvent;
      const raw = customEvent.detail?.message;
      if (!raw) return;
      const data = typeof raw === "string" ? JSON.parse(raw) : raw;
      handler(data);
    };

    window.addEventListener("HybridWebViewMessageReceived", listener);
    return () =>
      window.removeEventListener("HybridWebViewMessageReceived", listener);
  }
}
