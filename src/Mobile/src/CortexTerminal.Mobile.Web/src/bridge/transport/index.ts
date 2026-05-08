/* eslint-disable @typescript-eslint/no-explicit-any */
import type { Transport } from "./types";
import { HybridWebViewTransport } from "./HybridWebViewTransport";
import { FetchTransport } from "./FetchTransport";

/**
 * Check if we're running inside a real MAUI HybridWebView container.
 * The JS shim (hybridwebview.ts) always creates window.HybridWebView,
 * so we must check for the actual native host objects instead.
 *
 * - Windows/WebView2: window.chrome.webview
 * - iOS/MacCatalyst: window.webkit.messageHandlers.webwindowinterop
 * - Android: window.hybridWebViewHost
 */
function isNativeHybridWebView(): boolean {
  const w = window as any;
  return !!(
    w.chrome?.webview ||
    w.webkit?.messageHandlers?.webwindowinterop ||
    w.hybridWebViewHost
  );
}

/**
 * Auto-detect the transport based on the current environment.
 * If running inside a real MAUI HybridWebView, use the native bridge.
 * Otherwise, fall back to fetch + SSE for debug mode.
 */
function createTransport(): Transport {
  if (isNativeHybridWebView()) {
    return new HybridWebViewTransport();
  }
  return new FetchTransport();
}

export const transport: Transport = createTransport();
export type { Transport };
