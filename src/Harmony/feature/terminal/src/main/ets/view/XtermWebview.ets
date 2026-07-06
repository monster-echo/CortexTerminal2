/**
 * @file XtermWebview.ets
 * @brief ArkWeb container for xterm.js terminal rendering
 *
 * Hosts an ArkWeb (WebView) component that loads xterm.js for
 * terminal rendering. Handles bidirectional communication between
 * the native transport layer and the web-based terminal emulator.
 * Uses WebMessagePort for JS→Native input (replacing crash-prone javaScriptProxy).
 */
import { webview } from '@kit.ArkWeb'

type OnInputReadyCallback = () => void
type OnInputCallback = (data: string) => void
type OnResizeCallback = (cols: number, rows: number) => void

@Component
export struct XtermWebview {
  webviewController: webview.WebviewController = new webview.WebviewController()
  onInputReady: OnInputReadyCallback = () => {}
  onInput: OnInputCallback = (_data: string) => {}
  onResize: OnResizeCallback = (_cols: number, _rows: number) => {}
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('terminalCols') terminalCols: number = 80
  @StorageLink('terminalRows') terminalRows: number = 24

  private msgPorts: webview.WebMessagePort[] = []
  private readyNotified: boolean = false

  build() {
    Column() {
      Web({ src: $rawfile('xterm/index.html'), controller: this.webviewController, renderMode: RenderMode.SYNC_RENDER })
        .width('100%')
        .height('100%')
        .backgroundColor('#121414')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .zoomAccess(false)
        .databaseAccess(true)
        .cacheMode(CacheMode.Default)
        .darkMode(WebDarkMode.On)
        .focusable(true)
        .onPageEnd(() => {
          this.initMessagePort()
          this.webviewController.onActive()
          this.onWebviewReady()
        })
        .onConsole((event) => {
          console.info('[WebView] ' + event.message.getMessage())
          return true
        })
    }
    .width('100%')
    .height('100%')
  }

  private initMessagePort() {
    try {
      this.msgPorts = this.webviewController.createWebMessagePorts()
      console.info('[XtermWebview] ports created, length=' + this.msgPorts.length)
      this.msgPorts[1].onMessageEvent((result: webview.WebMessage) => {
        if (typeof result === 'string') {
          try {
            const msg = JSON.parse(result) as Record<string, Object>
            const type = msg['type'] as string
            if (type === 'input') {
              this.onInput(msg['data'] as string)
            } else if (type === 'resize') {
              const cols = msg['cols'] as number
              const rows = msg['rows'] as number
              if (cols > 0 && rows > 0) {
                this.onResize(cols, rows)
              }
            }
          } catch (e) {
            console.warn('[XtermWebview] onInput handler error: ' + (e as Error).message)
          }
        }
      })
      this.webviewController.postMessage('__init_port__', [this.msgPorts[0]], '*')
      console.info('[XtermWebview] port0 sent to HTML')
    } catch (e) {
      console.error('[XtermWebview] initMessagePort failed: ' + (e as Error).message)
    }
  }

  private onWebviewReady() {
    try {
      this.webviewController.requestFocus()
    } catch (_e) {}
    setTimeout(() => {
      this.tryInitializeTerminal(0)
    }, 50)
  }

  private tryInitializeTerminal(attempt: number) {
    if (this.readyNotified) {
      return
    }

    try {
      this.webviewController.runJavaScript(`
        (function () {
          if (typeof initTerminal === 'function') {
          initTerminal(${this.terminalCols}, ${this.terminalRows});
            return 'ready';
          }
          return 'missing';
        })();
      `)
        .then((result: string) => {
          if (result.indexOf('ready') >= 0 || attempt >= 2) {
            this.readyNotified = true
            try {
              this.webviewController.runJavaScript(
                "var ta = document.querySelector('.xterm-helper-textarea'); if(ta) ta.focus();"
              )
            } catch (_e) {}
            this.onInputReady()
            return
          }
          setTimeout(() => {
            this.tryInitializeTerminal(attempt + 1)
          }, 120)
        })
        .catch((e: Error) => {
          this.handleInitFailure(e, attempt)
        })
    } catch (e) {
      this.handleInitFailure(e as Error, attempt)
    }
  }

  private handleInitFailure(e: Error, attempt: number) {
    if (attempt < 2) {
      setTimeout(() => {
        this.tryInitializeTerminal(attempt + 1)
      }, 120)
      return
    }
    console.warn('Failed to init xterm: ' + e.message)
    this.readyNotified = true
    try {
      this.webviewController.runJavaScript(
        "var ta = document.querySelector('.xterm-helper-textarea'); if(ta) ta.focus();"
      )
    } catch (_e2) {}
    this.onInputReady()
  }

  writeOutput(base64Payload: string) {
    try {
      const escaped = base64Payload.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
      this.webviewController.runJavaScript(`writeBase64Output("${escaped}")`)
    } catch (e) {
      console.warn('Failed to write output: ' + (e as Error).message)
    }
  }

  resize(cols: number, rows: number) {
    try {
      this.webviewController.runJavaScript(`resizeTerminal(${cols}, ${rows})`)
    } catch (e) {
      console.warn('Failed to resize terminal: ' + (e as Error).message)
    }
  }
}
