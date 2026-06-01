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
import { TransportFrame } from '../model/TerminalTransportModels'
import { TerminalState } from '../model/TerminalState'
import { StatusStrip } from './StatusStrip'
import { XtermWebview } from './XtermWebview'
import { VirtualKeyBar } from './VirtualKeyBar'

class TerminalSize { cols: number = 0; rows: number = 0 }

@Component
export struct TerminalPage {
  @StorageLink('navSessionId') sessionId: string = ''
  @StorageLink('navSessionName') sessionName: string = 'Terminal'
  @State currentState: TerminalState = TerminalState.Disconnected
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('isKeyboardVisible') isKeyboardVisible: boolean = false
  @StorageLink('keyboardHeight') @Watch('onKeyboardHeightChange') keyboardHeight: number = 0
  @State connectionError: string = ''
  @State latencyMs: number = -1
  @State lastPingTime: number = 0
  private stateManager: TerminalStateManager = new TerminalStateManager()
  private transport: TerminalTransport = new TerminalTransport()
  private webviewController: webview.WebviewController = new webview.WebviewController()
  private lastCols: number = 80
  private lastRows: number = 24
  private webviewReady: boolean = false
  private terminalLive: boolean = false
  private initialFitDone: boolean = false
  private pendingOutput: string[] = []
  private connectTimer: number = -1

  onKeyboardHeightChange() {
    if (this.webviewReady) {
      setTimeout(() => { this.fitAndResize() }, 100)
    }
  }

  aboutToAppear() {
    this.stateManager.onStateChanged = (state: TerminalState) => {
      this.currentState = state
    }
    this.connectSession()
  }

  aboutToDisappear() {
    if (this.connectTimer !== -1) {
      clearTimeout(this.connectTimer)
      this.connectTimer = -1
    }
    this.transport.disconnect()
  }

  build() {
    Column() {
      // Top bar with session name and back button
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.terminal_primary')])
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

        // Latency badge + status indicator
        Row() {
          Circle()
            .width(7)
            .height(7)
            .fill(this.getStatusDotColor())

          Text(this.latencyMs >= 0 ? `${this.latencyMs}ms` : this.getStatusLabel())
            .fontSize(12)
            .fontColor(this.getStatusTextColor())
            .margin({ left: 6 })
        }
        .height(28)
        .padding({ left: 10, right: 10 })
        .borderRadius(14)
        .backgroundColor(this.getStatusBadgeBg())
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      // Status strip
      StatusStrip({ currentState: this.currentState })

      if (this.currentState === TerminalState.Error && this.connectionError.length > 0) {
        Row() {
          Column() {
            Text(this.connectionError)
              .fontSize(12)
              .fontColor($r('app.color.terminal_error'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Button('重试连接')
              .height(32)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .fontSize(12)
              .margin({ top: 8 })
              .onClick(() => {
                this.retryConnection()
              })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor('#1AFF4444')
      }

      // Xterm webview (main terminal area)
      XtermWebview({
        webviewController: this.webviewController,
        onInputReady: () => {
          this.webviewReady = true
          this.doInitialFit()
        },
        onInput: (data: string) => {
          this.sendInput(data)
        },
        onResize: (cols: number, rows: number) => {
          if (cols > 0 && rows > 0 && (cols !== this.lastCols || rows !== this.lastRows)) {
            this.lastCols = cols
            this.lastRows = rows
            if (this.terminalLive) {
              this.transport.sendResize(cols, rows)
            }
          }
        }
      })
      .layoutWeight(1)

      // Virtual key bar (visible only when keyboard is shown)
      if (this.isKeyboardVisible) {
        VirtualKeyBar({
          onKeyPress: (key: string) => {
            this.handleVirtualKey(key)
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private async connectSession() {
    this.connectionError = ''
    this.terminalLive = false
    this.stateManager.setState(TerminalState.Connecting)

    this.connectTimer = setTimeout(() => {
      if (this.currentState === TerminalState.Connecting) {
        this.connectionError = '连接超时，请重试'
        this.stateManager.setState(TerminalState.Error)
        this.transport.disconnect()
      }
    }, 15000) as number

    try {
      this.transport.onFrame = (frame: TransportFrame) => {
        this.handleFrame(frame)
      }

      this.transport.onDisconnected = () => {
        if (this.currentState !== TerminalState.Detached &&
          this.currentState !== TerminalState.Exited &&
          this.currentState !== TerminalState.Error) {
          this.connectionError = '连接已断开，正在重新连接'
          this.stateManager.setState(TerminalState.Reconnecting)
        }
      }

      await this.transport.connect(this.sessionId, this.authToken, this.gatewayUrl)
      // State will be set to Replaying/Live by the server frames
    } catch (e) {
      if (this.connectTimer !== -1) {
        clearTimeout(this.connectTimer)
        this.connectTimer = -1
      }
      this.connectionError = (e as Error).message || '连接网关失败'
      this.stateManager.setState(TerminalState.Error)
      console.error('Failed to connect terminal session: ' + this.connectionError)
    }
  }

  private handleFrame(frame: TransportFrame) {
    if (this.connectTimer !== -1) {
      clearTimeout(this.connectTimer)
      this.connectTimer = -1
    }

    switch (frame.type) {
      case 'output':
      case 'replay':
        this.writeOutput(frame.payload)
        break

      case 'replaying':
        this.stateManager.setState(TerminalState.Replaying)
        break

      case 'replayCompleted':
        try {
          this.webviewController.runJavaScript('clearTerminal()')
        } catch (e) {
          console.warn('Failed to clear terminal: ' + (e as Error).message)
        }
        break

      case 'live':
        this.connectionError = ''
        this.terminalLive = true
        this.stateManager.setState(TerminalState.Live)
        setTimeout(() => { this.fitAndResizeIfReady() }, 200)
        break

      case 'pong':
        break

      case 'latencyAck':
        console.info(`[TerminalPage] latencyAck: clientTime=${frame.clientTime}ms, probeId=${frame.probeId}`)
        if (frame.clientTime >= 0) {
          this.latencyMs = frame.clientTime
        }
        break

      case 'error':
        this.connectionError = `${frame.code}: ${frame.message}`
        this.stateManager.setState(TerminalState.Error)
        break

      case 'expired':
        this.connectionError = frame.reason || '会话已过期'
        this.stateManager.setState(TerminalState.Expired)
        break

      case 'exited':
        this.connectionError = frame.reason || '终端进程已退出'
        this.stateManager.setState(TerminalState.Exited)
        break
    }
  }

  private writeOutput(payload: string) {
    if (!this.webviewReady) {
      this.pendingOutput.push(payload)
      return
    }
    try {
      console.info(`[TerminalPage] writeOutput: ${payload.substring(0, 60)}`)
      this.webviewController.runJavaScript(`writeBase64Output("${payload}")`)
    } catch (e) {
      console.warn('Failed to write terminal output: ' + (e as Error).message)
    }
  }

  private flushPendingOutput() {
    if (!this.webviewReady || this.pendingOutput.length === 0) {
      return
    }
    const output = this.pendingOutput
    this.pendingOutput = []
    for (const payload of output) {
      this.writeOutput(payload)
    }
  }

  private retryConnection() {
    this.transport.disconnect()
    this.connectSession()
  }

  private doInitialFit() {
    if (this.initialFitDone) {
      return
    }
    this.initialFitDone = true
    this.fitAndResize().then(() => {
      this.flushPendingOutput()
    }).catch(() => {
      this.flushPendingOutput()
    })
  }

  private fitAndResizeIfReady() {
    if (!this.webviewReady || !this.terminalLive) {
      return
    }
    this.fitAndResize()
  }

  private fitAndResize(): Promise<void> {
    return new Promise<void>((resolve) => {
      try {
        this.webviewController.runJavaScript('fitTerminal()')
          .then(() => {
            return this.webviewController.runJavaScript('getTerminalSize()')
          })
          .then((result: string) => {
            const size = JSON.parse(result) as TerminalSize
            if (size.cols && size.rows &&
              (size.cols !== this.lastCols || size.rows !== this.lastRows)) {
              this.lastCols = size.cols
              this.lastRows = size.rows
              if (this.terminalLive) {
                this.transport.sendResize(this.lastCols, this.lastRows)
              }
            }
            resolve()
          })
          .catch(() => {
            resolve()
          })
      } catch (e) {
        resolve()
      }
    })
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
    console.info(`[TerminalPage] sendInput: data="${data}" (len=${data.length})`)
    const base64 = this.stringToBase64(data)
    console.info(`[TerminalPage] sendInput: base64=${base64}`)
    this.transport.sendInput(base64)
  }

  private stringToBase64(str: string): string {
    const bytes: number[] = []
    for (let i = 0; i < str.length; i++) {
      bytes.push(str.charCodeAt(i) & 0xFF)
    }
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let result = ''
    for (let i = 0; i < bytes.length; i += 3) {
      const b0 = bytes[i]
      const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0
      const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0
      result += chars.charAt(b0 >> 2)
      result += chars.charAt(((b0 & 3) << 4) | (b1 >> 4))
      result += i + 1 < bytes.length ? chars.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '='
      result += i + 2 < bytes.length ? chars.charAt(b2 & 63) : '='
    }
    return result
  }

  private getStatusDotColor(): ResourceColor {
    switch (this.currentState) {
      case TerminalState.Live:
        if (this.latencyMs > 300) return $r('app.color.terminal_error')
        if (this.latencyMs > 100) return '#FFC107'
        return $r('app.color.terminal_tertiary')
      case TerminalState.Connecting:
      case TerminalState.Reconnecting:
      case TerminalState.Replaying:
        return '#FFC107'
      case TerminalState.Expired:
      case TerminalState.Error:
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_outline_variant')
    }
  }

  private getStatusTextColor(): ResourceColor {
    switch (this.currentState) {
      case TerminalState.Live:
        return $r('app.color.terminal_on_surface_variant')
      case TerminalState.Expired:
      case TerminalState.Error:
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_on_surface_variant')
    }
  }

  private getStatusBadgeBg(): ResourceColor {
    return $r('app.color.terminal_surface_container')
  }

  private getStatusLabel(): string {
    switch (this.currentState) {
      case TerminalState.Live:
        return 'Live'
      case TerminalState.Connecting:
        return 'Connecting'
      case TerminalState.Reconnecting:
        return 'Reconnecting'
      case TerminalState.Replaying:
        return 'Replaying'
      case TerminalState.Error:
        return 'Error'
      case TerminalState.Expired:
        return 'Expired'
      default:
        return '...'
    }
  }

  private handleBack() {
    this.transport.sendDetach()
    this.stateManager.setState(TerminalState.Detached)
    this.pageStack.replacePath({ name: 'TerminalHome' })
  }
}
