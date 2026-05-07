/**
 * @file XtermWebview.ets
 * @brief ArkWeb container for xterm.js terminal rendering
 *
 * Hosts an ArkWeb (WebView) component that loads xterm.js for
 * terminal rendering. Handles bidirectional communication between
 * the native transport layer and the web-based terminal emulator.
 */
import { webview } from '@kit.ArkWeb'

/**
 * Callback type for when the webview is ready for input.
 */
type OnInputReadyCallback = () => void

/**
 * Proxy object for JavaScript bridge methods.
 */
class NativeTerminalProxy {
  sendInput(_data: string): void {}
}

@Component
export struct XtermWebview {
  @Prop webviewController: webview.WebviewController = new webview.WebviewController()
  @Prop onInputReady: OnInputReadyCallback = () => {}
  @StorageLink('gatewayUrl') gatewayUrl: string = ''

  // JavaScript port for receiving messages from xterm.js
  private jsPort: NativeTerminalProxy = new NativeTerminalProxy()

  build() {
    Column() {
      Web({ src: $rawfile('xterm/index.html'), controller: this.webviewController })
        .width('100%')
        .height('100%')
        .backgroundColor('#1a1b26')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .zoomAccess(false)
        .databaseAccess(true)
        .cacheMode(CacheMode.Default)
        .darkMode(WebDarkMode.On)
        .onPageEnd(() => {
          this.onWebviewReady()
        })
        .javaScriptProxy({
          object: this.jsPort,
          name: 'NativeTerminal',
          methodList: ['sendInput'],
          controller: this.webviewController
        })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * Called when the webview finishes loading the xterm.html page.
   * Initializes the terminal and signals readiness.
   */
  private onWebviewReady() {
    // Initialize xterm.js with appropriate dimensions
    try {
      this.webviewController.runJavaScript(`
        if (typeof initTerminal === 'function') {
          initTerminal();
        }
      `)
    } catch (e) {
      console.warn('Failed to init xterm: ' + (e as Error).message)
    }
    this.onInputReady()
  }

  /**
   * Send output data to the xterm.js terminal for rendering.
   * @param base64Payload Base64-encoded terminal output data.
   */
  writeOutput(base64Payload: string) {
    try {
      const escaped = base64Payload.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
      this.webviewController.runJavaScript(`handleOutput("${escaped}")`)
    } catch (e) {
      console.warn('Failed to write output: ' + (e as Error).message)
    }
  }

  /**
   * Notify xterm.js of a terminal resize event.
   * @param cols New column count
   * @param rows New row count
   */
  resize(cols: number, rows: number) {
    try {
      this.webviewController.runJavaScript(`resizeTerminal(${cols}, ${rows})`)
    } catch (e) {
      console.warn('Failed to resize terminal: ' + (e as Error).message)
    }
  }
}
