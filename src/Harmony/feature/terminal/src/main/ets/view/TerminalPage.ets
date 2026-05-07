/**
 * @file TerminalPage.ets
 * @brief Main terminal screen with xterm webview, status strip, and key bar
 *
 * Layout: Top bar -> StatusStrip -> XtermWebview -> VirtualKeyBar
 * Manages the terminal session lifecycle via TerminalStateManager.
 * Handles background/foreground session recovery and keyboard resize.
 */
import { buffer } from '@kit.ArkTS'
import { webview } from '@kit.ArkWeb'
import { TerminalStateManager } from '../service/TerminalStateManager'
import { TerminalTransport } from '../service/TerminalTransport'
import { TerminalState } from '../model/TerminalState'
import { StatusStrip } from './StatusStrip'
import { XtermWebview } from './XtermWebview'
import { VirtualKeyBar } from './VirtualKeyBar'

@Component
export struct TerminalPage {
  @StorageLink('navSessionId') sessionId: string = ''
  @StorageLink('navSessionName') sessionName: string = 'Terminal'
  @State currentState: TerminalState = TerminalState.Disconnected
  @State keyBarExpanded: boolean = false
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''
  @StorageLink('isKeyboardVisible') isKeyboardVisible: boolean = false
  @StorageLink('keyboardHeight') keyboardHeight: number = 0
  private stateManager: TerminalStateManager = new TerminalStateManager()
  private transport: TerminalTransport = new TerminalTransport()
  private webviewController: webview.WebviewController = new webview.WebviewController()
  private lastCols: number = 80
  private lastRows: number = 24

  aboutToAppear() {
    this.stateManager.onStateChanged = (state: TerminalState) => {
      this.currentState = state
    }
    this.connectSession()
  }

  aboutToDisappear() {
    this.transport.disconnect()
  }

  build() {
    Column() {
      // Top bar with session name and back button
      Row() {
        Button() {
          Text('<')
            .fontSize(20)
            .fontColor($r('app.color.terminal_primary'))
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.handleBack()
        })

        Text(this.sessionName)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })

        // Detach button
        Button() {
          Text('Detach')
            .fontSize(13)
            .fontColor($r('app.color.terminal_secondary'))
        }
        .height(32)
        .borderRadius(8)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.transport.sendDetach()
        })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      // Status strip
      StatusStrip({ currentState: this.currentState })

      // Xterm webview (main terminal area)
      XtermWebview({
        webviewController: this.webviewController,
        onInputReady: () => {
          // Webview initialized — trigger initial fit
          this.fitAndResize()
        }
      })
      .layoutWeight(1)

      // Virtual key bar (only show when hardware keyboard is not active)
      if (!this.isKeyboardVisible) {
        VirtualKeyBar({
          onKeyPress: (key: string) => {
            this.handleVirtualKey(key)
          },
          expanded: this.keyBarExpanded,
          onToggleExpand: () => {
            this.keyBarExpanded = !this.keyBarExpanded
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private async connectSession() {
    this.stateManager.setState(TerminalState.Connecting)

    try {
      this.transport.onFrame = (frame: Record<string, Object>) => {
        this.handleFrame(frame)
      }

      this.transport.onDisconnected = () => {
        if (this.currentState !== TerminalState.Detached &&
          this.currentState !== TerminalState.Exited) {
          this.stateManager.setState(TerminalState.Reconnecting)
        }
      }

      await this.transport.connect(this.sessionId, this.authToken, this.gatewayUrl)
      // State will be set to Replaying/Live by the server frames
    } catch (e) {
      this.stateManager.setState(TerminalState.Error)
      console.error('Failed to connect terminal session: ' + (e as Error).message)
    }
  }

  private handleFrame(frame: Record<string, Object>) {
    const type = frame['type'] as string ?? ''

    switch (type) {
      case 'output':
      case 'replay':
        const payload = frame['payload'] as string ?? ''
        try {
          this.webviewController.runJavaScript(`writeBase64Output("${payload}")`)
        } catch (e) {
          console.warn('Failed to write terminal output: ' + (e as Error).message)
        }
        break

      case 'replaying':
        this.stateManager.setState(TerminalState.Replaying)
        break

      case 'replayCompleted':
        // Clear terminal before going live to avoid stale replay + live overlap
        try {
          this.webviewController.runJavaScript('clearTerminal()')
        } catch (e) {
          console.warn('Failed to clear terminal: ' + (e as Error).message)
        }
        break

      case 'live':
        this.stateManager.setState(TerminalState.Live)
        // After going live, fit terminal to container and send resize
        setTimeout(() => { this.fitAndResize() }, 200)
        break

      case 'pong':
        break

      case 'latencyAck':
        break

      case 'error':
        this.stateManager.setState(TerminalState.Error)
        break

      case 'expired':
        this.stateManager.setState(TerminalState.Expired)
        break

      case 'exited':
        this.stateManager.setState(TerminalState.Exited)
        break
    }
  }

  /**
   * Fit the xterm terminal to its container and send resize to the PTY.
   */
  private fitAndResize() {
    try {
      this.webviewController.runJavaScript('fitTerminal()')
      // Read the actual terminal size after fitting
      this.webviewController.runJavaScript('getTerminalSize()')
        .then((result: string) => {
          const size = JSON.parse(result) as Record<string, number>
          if (size['cols'] && size['rows'] &&
            (size['cols'] !== this.lastCols || size['rows'] !== this.lastRows)) {
            this.lastCols = size['cols']
            this.lastRows = size['rows']
            this.transport.sendResize(this.lastCols, this.lastRows)
          }
        })
        .catch(() => {
          // Ignore — terminal not yet ready
        })
    } catch (e) {
      // Ignore fit errors
    }
  }

  private handleVirtualKey(key: string) {
    const inputMap: Record<string, string> = {
      'Escape': '\x1b',
      'Tab': '\t',
      'ArrowUp': '\x1b[A',
      'ArrowDown': '\x1b[B',
      'ArrowRight': '\x1b[C',
      'ArrowLeft': '\x1b[D'
    }

    if (inputMap[key]) {
      this.sendInput(inputMap[key])
    } else if (key.startsWith('Ctrl+')) {
      const ch = key.substring(5).toLowerCase().charCodeAt(0)
      if (ch >= 97 && ch <= 122) {
        this.sendInput(String.fromCharCode(ch - 96))
      }
    } else if (key.startsWith('Alt+')) {
      this.sendInput('\x1b' + key.substring(4))
    } else {
      this.sendInput(key)
    }
  }

  private sendInput(data: string) {
    const base64 = this.stringToBase64(data)
    this.transport.sendInput(base64)
  }

  private stringToBase64(str: string): string {
    const bytes: number[] = []
    for (let i = 0; i < str.length; i++) {
      const code = str.charCodeAt(i)
      bytes.push(code & 0xFF)
    }
    let binary = ''
    for (const byte of bytes) {
      binary += String.fromCharCode(byte)
    }
    return buffer.from(binary, 'binary').toString('base64')
  }

  private handleBack() {
    this.transport.sendDetach()
    this.stateManager.setState(TerminalState.Detached)
  }
}
