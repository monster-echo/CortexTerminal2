/* eslint-disable @typescript-eslint/no-explicit-any */
import type { Transport } from "./types";

/**
 * Debug transport using fetch + SSE to communicate with the DebugApi server.
 */
export class FetchTransport implements Transport {
  async invoke(methodName: string, args: unknown[]): Promise<any> {
    const response = await fetch(`/api/bridge/${methodName}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });

    if (!response.ok) {
      throw new Error(
        `Bridge call failed: ${methodName} (${response.status})`,
      );
    }

    const text = await response.text();
    return text;
  }

  sendRaw(message: unknown): void {
    fetch("/api/bridge/raw", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(message),
    }).catch((err) => {
      console.warn("Failed to send raw message:", err);
    });
  }

  onMessage(handler: (data: unknown) => void): () => void {
    const eventSource = new EventSource("/api/bridge/events");

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        handler(data);
      } catch {
        console.warn("Failed to parse SSE event:", event.data);
      }
    };

    eventSource.onerror = () => {
      console.warn("SSE connection error, reconnecting...");
    };

    return () => {
      eventSource.close();
    };
  }
}
