/**
 * @file TerminalPage.ets
 * @brief Main terminal screen with xterm webview, status strip, and key bar
 *
 * Layout: Top bar -> XtermWebview -> VirtualKeyBar
 * Manages the terminal session lifecycle via TerminalStateManager.
 * Handles background/foreground session recovery and keyboard resize.
 */
import { buffer } from '@kit.ArkTS'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { pasteboard } from '@kit.BasicServicesKit'
import { TerminalNavParam, RouteName, I18n, AnalyticsService, lightHaptic, clickHaptic } from '@rwecho/core'
import { TerminalStateManager } from '../service/TerminalStateManager'
import { TerminalTransport } from '../service/TerminalTransport'
import { TransportFrame } from '../model/TerminalTransportModels'
import { TerminalState } from '../model/TerminalState'
import { XtermWebview } from './XtermWebview'
import { VirtualKeyBar } from './VirtualKeyBar'

class TerminalSize { cols: number = 0; rows: number = 0 }

@CustomDialog
struct SessionDetailDialog {
  controller: CustomDialogController
  status: string = ''
  cols: number = 0
  rows: number = 0
  latencyMs: number = -1

  build() {
    WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Column() {
      Text(I18n.get('terminal.detail.title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 12 })

      Row() {
        Text(I18n.get('terminal.detail.status'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .layoutWeight(1)
        Text(this.status)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
      }
      .width('100%')
      .height(36)
      .border({ width: { bottom: 0.5 }, color: $r('app.color.terminal_outline_variant') })

      Row() {
        Text(I18n.get('terminal.detail.cols'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .layoutWeight(1)
        Text(`${this.cols}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
      }
      .width('100%')
      .height(36)
      .border({ width: { bottom: 0.5 }, color: $r('app.color.terminal_outline_variant') })

      Row() {
        Text(I18n.get('terminal.detail.rows'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .layoutWeight(1)
        Text(`${this.rows}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
      }
      .width('100%')
      .height(36)
      .border({ width: { bottom: 0.5 }, color: $r('app.color.terminal_outline_variant') })

      Row() {
        Text(I18n.get('terminal.detail.latency'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .layoutWeight(1)
        Text(this.latencyMs >= 0 ? `${this.latencyMs}ms` : '—')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
      }
      .width('100%')
      .height(36)

      Button(I18n.get('terminal.detail.confirm'))
        .width('100%')
        .height(40)
        .margin({ top: 16 })
        .fontSize(15)
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .borderRadius(10)
        .onClick(() => {
          clickHaptic()
          this.controller.close()
        })
    }
    .padding(20)
    .borderRadius(16)
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .width('80%')
    .constraintSize({ maxWidth: 320 })
    }
  }
}

@Component
export struct TerminalPage {
  @State sessionId: string = ''
  @State sessionName: string = 'Terminal'
  @State currentState: TerminalState = TerminalState.Disconnected
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''
  @StorageLink('language') currentLang: string = 'en'
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('isKeyboardVisible') isKeyboardVisible: boolean = false
  @StorageLink('keyboardHeight') @Watch('onKeyboardHeightChange') keyboardHeight: number = 0
  @State connectionError: string = ''
  @State latencyMs: number = -1
  @State lastPingTime: number = 0
  @State ctrlActive: boolean = false
  @State altActive: boolean = false
  private detailDialog: CustomDialogController = new CustomDialogController({
    builder: SessionDetailDialog({ status: '', cols: 0, rows: 0, latencyMs: -1 }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  private stateManager: TerminalStateManager = new TerminalStateManager()
  private transport: TerminalTransport = new TerminalTransport()
  private webviewController: webview.WebviewController = new webview.WebviewController()
  private lastCols: number = 80
  private lastRows: number = 24
  private webviewReady: boolean = false
  private terminalLive: boolean = false
  private initialFitDone: boolean = false
  private pendingBatch: string[] = []
  private flushScheduled: boolean = false
  private connectTimer: number = -1
  private pageVisible: boolean = true

  private applyStatusBar(forceWhite: boolean): void {
    const context = getContext(this) as common.UIAbilityContext
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarContentColor: forceWhite ? '#ffffff' : '#000000'
      })
    }).catch(() => {})
  }

  onKeyboardHeightChange() {
    if (this.webviewReady) {
      setTimeout(() => { this.fitAndResize() }, 100)
    }
  }

  aboutToAppear() {
    AnalyticsService.onPageStart('terminal/Session')
    this.pageVisible = true
    // Read session params from NavPathStack navigation parameter
    const param = this.pageStack.getParamByName('terminal/Session') as TerminalNavParam[]
    if (param && param.length > 0) {
      const lastParam = param[param.length - 1]
      this.sessionId = lastParam.sessionId
      this.sessionName = lastParam.sessionName || 'Terminal'
    }
    this.stateManager.onStateChanged = (state: TerminalState) => {
      this.currentState = state
    }
    // Only reconnect if transport is not already connected
    if (!this.transport.isConnected) {
      this.connectSession()
    }
    // Terminal always uses dark theme — set white status bar text
    AppStorage.setOrCreate('terminalPageActive', true)
    this.applyStatusBar(true)
  }

  aboutToDisappear() {
    AppStorage.setOrCreate('terminalPageActive', false)
    const isDark = AppStorage.get<string>('colorMode') !== 'light'
    this.applyStatusBar(isDark)
    this.pageVisible = false
    if (this.connectTimer !== -1) {
      clearTimeout(this.connectTimer)
      this.connectTimer = -1
    }
    this.transport.sendDetach()
  }

  build() {
    WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Column() {
      // Custom AppBar with status badge
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
          clickHaptic()
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
        .onClick(() => {
          lightHaptic()
          this.showSessionDetail()
        })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.currentState === TerminalState.Error && this.connectionError.length > 0) {
        Row() {
          Column() {
            Text(this.connectionError)
              .fontSize(12)
              .fontColor($r('app.color.terminal_error'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Button(I18n.get('terminal.error.retry_connection'))
              .height(32)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .fontSize(12)
              .margin({ top: 8 })
              .onClick(() => {
                clickHaptic()
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
          if (this.ctrlActive) {
            this.sendInput(this.applyCtrl(data))
          } else if (this.altActive) {
            this.sendInput('\x1b' + data)
          } else {
            this.sendInput(data)
          }
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

      // Virtual key bar (visible when keyboard is shown)
      if (this.isKeyboardVisible) {
        VirtualKeyBar({
          onKeyPress: (key: string) => {
            this.handleVirtualKey(key)
          },
          onDismiss: () => {
            this.dismissKeyboard()
          },
          onModifierChange: (ctrl: boolean, alt: boolean) => {
            this.ctrlActive = ctrl
            this.altActive = alt
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
    }
  }

  private async connectSession() {
    this.connectionError = ''
    this.terminalLive = false
    this.stateManager.setState(TerminalState.Connecting)

    this.connectTimer = setTimeout(() => {
      if (this.currentState === TerminalState.Connecting) {
        this.connectionError = I18n.get('terminal.error.timeout')
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
          this.connectionError = I18n.get('terminal.error.disconnected')
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
      this.connectionError = (e as Error).message || I18n.get('terminal.error.gateway_failed')
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
        this.fitAndResizeIfReady()
        break

      case 'pong':
        break

      case 'latencyAck':
        if (frame.clientTime >= 0) {
          this.latencyMs = frame.clientTime
        }
        break

      case 'error':
        this.connectionError = `${frame.code}: ${frame.message}`
        this.stateManager.setState(TerminalState.Error)
        break

      case 'expired':
        this.connectionError = frame.reason || I18n.get('terminal.status.expired')
        this.stateManager.setState(TerminalState.Expired)
        setTimeout(() => {
          this.pageStack.replacePath({ name: RouteName.SESSION_HOME })
        }, 2000)
        break

      case 'exited':
        this.connectionError = frame.reason || I18n.get('terminal.error.process_exited')
        this.stateManager.setState(TerminalState.Exited)
        setTimeout(() => {
          this.pageStack.replacePath({ name: RouteName.SESSION_HOME })
        }, 2000)
        break
    }
  }

  private writeOutput(payload: string) {
    this.pendingBatch.push(payload)
    if (this.webviewReady && !this.flushScheduled) {
      this.flushScheduled = true
      setTimeout(() => { this.flushBatch() }, 16)
    }
  }

  private flushBatch() {
    this.flushScheduled = false
    if (this.pendingBatch.length === 0) {
      return
    }
    const packed = this.pendingBatch.join('|')
    this.pendingBatch = []
    try {
      this.webviewController.runJavaScript(`writeBatchedOutput("${packed}")`)
    } catch (e) {
      throw new Error('Failed to write terminal batch: ' + (e as Error).message)
    }
  }

  private flushPendingOutput() {
    if (!this.webviewReady || this.pendingBatch.length === 0) {
      return
    }
    this.flushBatch()
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
    // Ctrl+key combos from VirtualKeyBar's KeyButton latch logic
    const ctrlMap: Record<string, string> = {
      'Esc': '\x03',         // Ctrl+C (SIGINT), matches MAUI
      'ArrowUp': '\x1b[1;5A',
      'ArrowDown': '\x1b[1;5B',
      'ArrowRight': '\x1b[1;5C',
      'ArrowLeft': '\x1b[1;5D',
      'Home': '\x1b[1;5H',
      'End': '\x1b[1;5F',
    }

    if (key.startsWith('Ctrl+')) {
      const label = key.substring(5)
      const mapped = ctrlMap[label]
      if (mapped) {
        this.sendInput(mapped)
        return
      }
      // Single-letter Ctrl combo (a-z)
      const ch = label.toLowerCase().charCodeAt(0)
      if (ch >= 97 && ch <= 122) {
        this.sendInput(String.fromCharCode(ch - 96))
      }
    } else if (key.startsWith('Alt+')) {
      const label = key.substring(4)
      const altInput = inputMap[label]
      if (altInput) {
        this.sendInput('\x1b' + altInput)
      } else {
        this.sendInput('\x1b' + label)
      }
    } else if (inputMap[key]) {
      this.sendInput(inputMap[key])
    } else {
      this.sendInput(key)
    }
  }

  private applyCtrl(sequence: string): string {
    const code = sequence.charCodeAt(0)
    if (code === 0x1b) return '\x03'
    if (code >= 0x41 && code <= 0x5a) return String.fromCharCode(code - 64)
    if (code >= 0x61 && code <= 0x7a) return String.fromCharCode(code - 96)
    return sequence
  }

  private sendInput(data: string) {
    const base64 = this.stringToBase64(data)
    this.transport.sendInput(base64)
  }

  private stringToBase64(str: string): string {
    const buf = buffer.from(str, 'utf-8')
    return buf.toString('base64')
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

  private dismissKeyboard() {
    try {
      this.webviewController.runJavaScript(
        "var ta = document.querySelector('.xterm-helper-textarea'); if(ta) ta.blur();"
      )
    } catch (_e) {}
  }


  private showSessionDetail() {
    this.detailDialog = new CustomDialogController({
      builder: SessionDetailDialog({
        status: this.getStatusLabel(),
        cols: this.lastCols,
        rows: this.lastRows,
        latencyMs: this.latencyMs
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    })
    this.detailDialog.open()
  }

  private handleBack() {
    this.transport.sendDetach()
    this.stateManager.setState(TerminalState.Detached)
    this.pageStack.replacePath({ name: RouteName.SESSION_HOME })
  }
}
