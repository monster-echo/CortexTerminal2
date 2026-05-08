/**
 * Transport interface for bridge communication.
 * Implemented by HybridWebViewTransport (production) and FetchTransport (debug).
 */
export interface Transport {
  /**
   * Invoke a bridge method and return the raw result string.
   */
  invoke(methodName: string, args: unknown[]): Promise<any>;

  /**
   * Send a raw message (fire-and-forget) to the native side.
   */
  sendRaw(message: unknown): void;

  /**
   * Subscribe to push messages from the native side.
   * Returns an unsubscribe function.
   */
  onMessage(handler: (data: unknown) => void): () => void;
}
