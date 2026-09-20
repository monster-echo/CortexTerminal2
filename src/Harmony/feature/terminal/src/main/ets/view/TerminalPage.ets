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
import { ApiService, TerminalNavParam, RouteName, I18n, AnalyticsService, lightHaptic, clickHaptic, showToast } from '@rwecho/core'
import { TerminalCache, TerminalCacheEntry } from '../service/TerminalCache'
import { SnapshotStore } from '../service/SnapshotStore'
import { TerminalStateManager } from '../service/TerminalStateManager'
import { TerminalTransport } from '../service/TerminalTransport'
import { TransportFrame } from '../model/TerminalTransportModels'
import { TerminalState } from '../model/TerminalState'
import { XtermWebview } from './XtermWebview'
import { VirtualKeyBar } from './VirtualKeyBar'
import { TunnelPanel } from './TunnelPanel'

class TerminalSize { cols: number = 0; rows: number = 0 }

/** One JSON-encoded fragment handed to restoreSnapshotChunk() on the JS side. */
class SnapshotChunk {
  data: string = ''
}

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
  @StorageLink('appBackgroundTick') @Watch('onAppBackground') appBackgroundTick: number = 0
  @State connectionError: string = ''
  @State latencyMs: number = -1
  @State lastPingTime: number = 0
  @State ctrlActive: boolean = false
  @State altActive: boolean = false
  @State showTunnelSheet: boolean = false
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
  private isReplaying: boolean = false
  private pendingSwap: boolean = false
  private deltaMode: boolean = false
  private deltaPacked: string[] = []
  private replaySinceSeq: number = 0
  @State private terminalMenuVisible: boolean = false
  @State private menuX: number = 0
  @State private menuY: number = 0
  @State private menuHasSelection: boolean = false
  private pendingBatch: string[] = []
  private flushScheduled: boolean = false
  private connectTimer: number = -1
  private resizeDebounceTimer: number = -1
  private pageVisible: boolean = true
  // Scrollback snapshot (serialize → device file, keyed by WORKER so a new
  // session on the same machine restores the old history and appends below
  // it — Windows-Terminal-style concat). hasRestoredSnapshot marks a page
  // whose painted content came from the snapshot: the server's authoritative
  // full replay must not swap it away (for a new session that replay is
  // empty; for a re-opened dead session the snapshot already contains it).
  private snapshotKey: string = ''
  private hasRestoredSnapshot: boolean = false
  private snapshotIdleTimer: number = -1

  private applyStatusBar(forceWhite: boolean): void {
    const context = getContext(this) as common.UIAbilityContext
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarContentColor: forceWhite ? '#ffffff' : '#000000'
      })
    }).catch(() => {})
  }

  onKeyboardHeightChange() {
    if (!this.webviewReady) {
      return
    }
    // Debounce: keyboard show/hide updates keyboardHeight across many
    // animation frames. Without this each frame schedules a separate
    // fitAndResize → multiple xterm resize/redraws stack up (the "重刷").
    // Clear the pending fit and run only one after the height settles.
    if (this.resizeDebounceTimer !== -1) {
      clearTimeout(this.resizeDebounceTimer)
    }
    this.resizeDebounceTimer = setTimeout(() => {
      this.resizeDebounceTimer = -1
      this.fitAndResize()
    }, 150) as number
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
      // Snapshot key: the WORKER when known — every session on the same
      // machine shares one rolling history. Worker-less navigation falls
      // back to the session id (per-session snapshot, no cross concat).
      this.snapshotKey = lastParam.workerId.length > 0 ? lastParam.workerId : this.sessionId
      console.info(`[snapshot] key=${this.snapshotKey} session=${this.sessionId}`)
    }
    TerminalCache.getInstance().init(getContext(this).filesDir)
    this.replaySinceSeq = TerminalCache.getInstance().loadLastSeq(this.sessionId)
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
    if (this.resizeDebounceTimer !== -1) {
      clearTimeout(this.resizeDebounceTimer)
      this.resizeDebounceTimer = -1
    }
    if (this.snapshotIdleTimer !== -1) {
      clearTimeout(this.snapshotIdleTimer)
      this.snapshotIdleTimer = -1
    }
    // Best-effort capture on the way out — if the webview tears down before
    // the async serialize lands, the 3s idle saves already covered us.
    this.captureSnapshot()
    this.transport.sendDetach()
  }

  onAppBackground() {
    this.captureSnapshot()
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

        Button() {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(18)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          clickHaptic()
          this.showTunnelSheet = true
        })

        Button() {
          SymbolGlyph($r('sys.symbol.paperplane'))
            .fontSize(18)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          clickHaptic()
          this.openFiles()
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

      // Xterm webview (main terminal area) + context menu overlay.
      // The Stack shares the webview's coordinate space, so the menu anchored
      // at JS-reported client coords lands at the pressed cell.
      Stack() {
        XtermWebview({
          webviewController: this.webviewController,
          onInputReady: () => {
            this.webviewReady = true
            this.paintOnReady()
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
          },
          onContextMenu: (x: number, y: number) => {
            this.onTerminalContextMenu(x, y)
          },
          onSnapshotCaptured: (content: string) => {
            this.onSnapshotCaptured(content)
          },
          onSnapshotFailed: (message: string) => {
            this.onSnapshotFailed(message)
          }
        })

        if (this.terminalMenuVisible) {
          Row() {
            this.TerminalMenuButton(I18n.get('terminal.menu.copy'), this.menuHasSelection, () => {
              this.copyTerminalSelection()
            })
            this.TerminalMenuButton(I18n.get('terminal.menu.selectall'), true, () => {
              lightHaptic()
              this.webviewController.runJavaScript('selectAllTerminal()')
                .then(() => {
                  this.menuHasSelection = true
                })
                .catch((_e: Error) => {})
            })
            this.TerminalMenuButton(I18n.get('terminal.menu.paste'), true, () => {
              this.pasteFromClipboardToTerminal()
            })
            this.TerminalMenuButton(I18n.get('terminal.menu.cancel'), true, () => {
              this.webviewController.runJavaScript('clearSelection()')
              this.terminalMenuVisible = false
            })
          }
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_surface_container_highest'))
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.4)', offsetY: 2 })
          .position({ x: this.menuX, y: this.menuY })
        }
      }
      .layoutWeight(1)
      .alignContent(Alignment.TopStart)

      // Virtual key bar (visible when keyboard is shown)
      if (this.isKeyboardVisible) {
        VirtualKeyBar({
          onKeyPress: (key: string) => {
            this.handleVirtualKey(key)
          },
          onPasteText: (text: string) => {
            this.pasteTextToTerminal(text)
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
    .bindSheet($$this.showTunnelSheet, this.TunnelSheetContent(), {
      height: SheetSize.LARGE,
      showClose: true,
      backgroundColor: $r('app.color.terminal_surface'),
      onDisappear: () => { this.showTunnelSheet = false }
    })
    }
  }

  @Builder
  TunnelSheetContent() {
    TunnelPanel({
      sessionId: this.sessionId
    })
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

      await this.transport.connect(this.sessionId, this.authToken, this.gatewayUrl, this.replaySinceSeq)
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
        this.writeOutput(frame.payload)
        break

      case 'replay':
        // Buffer replay chunks without rendering; flushed in one write on
        // replayCompleted so the screen doesn't visibly redraw top-to-bottom.
        this.pendingBatch.push(frame.payload)
        break

      case 'replaying':
        // SessionReattached arrives before replay chunks. The authoritative
        // replay replaces whatever is on screen, but resetting now would blank
        // the terminal for the seconds the replay takes to stream. Keep the
        // locally cached screen painted, buffer the fresh chunks, and swap
        // atomically on replayCompleted (reset + single write + cache rewrite).
        this.isReplaying = true
        this.pendingBatch = []
        this.flushScheduled = false
        this.pendingSwap = true
        this.stateManager.setState(TerminalState.Replaying)
        break

      case 'replayCompleted':
        // The authoritative replay is fully buffered: swap it onto the screen
        // atomically (reset + single write) and rewrite the local cache from
        // the same bytes, so disk and screen can never disagree.
        this.isReplaying = false
        this.pendingSwap = true
        this.flushPendingOutput()
        break

      case 'replayDeltaStart':
        // Incremental reattach: the cached screen continues seamlessly — no
        // reset, no swap. Delta chunks paint as they arrive and the cursor
        // advances when the server confirms completion.
        this.isReplaying = true
        this.deltaMode = true
        this.deltaPacked = []
        this.stateManager.setState(TerminalState.Replaying)
        break

      case 'replayDelta':
        this.deltaPacked.push(frame.payload)
        this.writeOutput(frame.payload)
        break

      case 'replayDeltaCompleted':
        this.isReplaying = false
        this.deltaMode = false
        try {
          TerminalCache.getInstance().commitDelta(this.sessionId, this.deltaPacked.join('|'), frame.lastSeq)
        } catch (e) {
          console.error('Failed to commit terminal cache delta: ' + (e as Error).message)
        }
        this.deltaPacked = []
        this.flushPendingOutput()
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
        TerminalCache.getInstance().clear(this.sessionId)
        // Grab the final buffer now — the page auto-navigates in 2s and the
        // webview may not survive long enough for the aboutToDisappear save.
        this.captureSnapshot()
        this.stateManager.setState(TerminalState.Expired)
        setTimeout(() => {
          this.pageStack.replacePath({ name: RouteName.SESSION_HOME })
        }, 2000)
        break

      case 'exited':
        this.connectionError = frame.reason || I18n.get('terminal.error.process_exited')
        TerminalCache.getInstance().clear(this.sessionId)
        this.captureSnapshot()
        this.stateManager.setState(TerminalState.Exited)
        setTimeout(() => {
          this.pageStack.replacePath({ name: RouteName.SESSION_HOME })
        }, 2000)
        break
    }
  }

  private writeOutput(payload: string) {
    // Live output is painted only — it is never written to the cache. The
    // cache holds exclusively server-confirmed streams (full replays + applied
    // deltas), so its cursor can never claim bytes the server will resend.
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
    this.writePackedToWebview(packed)
    this.scheduleSnapshotSave()
  }

  private writePackedToWebview(packed: string) {
    try {
      this.webviewController.runJavaScript(`writeBatchedOutput("${packed}")`)
        .catch((e: Error) => {
          // Bridge-level failure (JS syntax error, webview gone) — surface it,
          // don't leave an unhandled rejection silently swallowing the batch.
          console.error('Failed to write terminal batch: ' + e.message)
        })
    } catch (e) {
      throw new Error('Failed to write terminal batch: ' + (e as Error).message)
    }
  }

  private runResetTerminal() {
    try {
      this.webviewController.runJavaScript('resetTerminal()').catch((e: Error) => {
        console.warn('Failed to reset terminal: ' + e.message)
      })
    } catch (e) {
      console.warn('Failed to reset terminal: ' + (e as Error).message)
    }
  }

  /**
   * Paint the moment the webview is up, choosing the richest local source:
   *   1. the session's server-confirmed cache (same-session re-entry — the
   *      delta replay continues seamlessly from its cursor), or
   *   2. the worker snapshot (no cache → first entry or a NEW session on the
   *      same worker — full 64k-line history; live output appends below it).
   * The server replay reconciles afterwards; swapReplayedScreen() keeps the
   * snapshot-painted screen when the two would only duplicate each other.
   */
  private paintOnReady() {
    let entry = new TerminalCacheEntry()
    let cacheBroken = false
    try {
      entry = TerminalCache.getInstance().load(this.sessionId)
    } catch (e) {
      console.error('Failed to load terminal cache: ' + (e as Error).message)
      cacheBroken = true
    }
    if (!cacheBroken && entry.packed.length > 0) {
      try {
        this.webviewController.runJavaScript(`writeBatchedOutput("${entry.packed}")`)
          .catch((e: Error) => {
            console.error('Failed to paint cached terminal: ' + e.message)
          })
      } catch (e) {
        console.error('Failed to paint cached terminal: ' + (e as Error).message)
      }
      return
    }
    this.restoreWorkerSnapshot()
  }

  /**
   * Replay the worker's snapshot into the buffer, chunked to keep each
   * runJavaScript payload in the size class the write path already proves
   * out on ArkWeb. runJavaScript is FIFO, so the chunks land in capture
   * order and everything flushed later appends BELOW them.
   */
  private restoreWorkerSnapshot() {
    if (!SnapshotStore.exists(this.snapshotKey)) {
      console.info(`[snapshot] none on device for key=${this.snapshotKey}`)
      return
    }
    let content = ''
    try {
      content = SnapshotStore.load(this.snapshotKey)
    } catch (e) {
      console.error('Failed to load terminal snapshot: ' + (e as Error).message)
      showToast(I18n.get('terminal.snapshot.load_failed'))
      return
    }
    if (content.length === 0) {
      return
    }
    console.info(`[snapshot] restoring ${content.length}B for key=${this.snapshotKey}`)
    const CHUNK = 262144
    try {
      for (let i = 0; i < content.length; i += CHUNK) {
        const piece = content.substring(i, Math.min(i + CHUNK, content.length))
        const chunk = new SnapshotChunk()
        chunk.data = piece
        const json = JSON.stringify(chunk)
        const escaped = json.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
        this.webviewController.runJavaScript(`restoreSnapshotChunk("${escaped}")`)
          .catch((e: Error) => console.warn('Failed to restore snapshot chunk: ' + e.message))
      }
      this.hasRestoredSnapshot = true
    } catch (e) {
      console.error('Failed to restore terminal snapshot: ' + (e as Error).message)
      showToast(I18n.get('terminal.snapshot.load_failed'))
    }
  }

  /** Serialize the live buffer to the device (async — result lands via onSnapshotCaptured). */
  private captureSnapshot() {
    if (!this.webviewReady) {
      return
    }
    try {
      this.webviewController.runJavaScript('startSnapshotCapture()')
        .catch((e: Error) => {
          this.onSnapshotFailed(e.message)
        })
    } catch (e) {
      this.onSnapshotFailed((e as Error).message)
    }
  }

  /** Output writes reset this — snapshots are taken 3s after the stream quiets. */
  private scheduleSnapshotSave() {
    if (this.snapshotIdleTimer !== -1) {
      clearTimeout(this.snapshotIdleTimer)
    }
    this.snapshotIdleTimer = setTimeout(() => {
      this.snapshotIdleTimer = -1
      this.captureSnapshot()
    }, 3000) as number
  }

  private onSnapshotCaptured(content: string) {
    // An empty buffer must never overwrite the previous snapshot: it would
    // erase the very history the next session on this worker is meant to
    // inherit. (An empty capture can only happen before anything rendered.)
    if (content.length === 0) {
      return
    }
    try {
      SnapshotStore.save(this.snapshotKey, content)
      console.info(`[snapshot] saved ${content.length}B key=${this.snapshotKey}`)
    } catch (e) {
      console.error('Failed to save terminal snapshot: ' + (e as Error).message)
      showToast(I18n.get('terminal.snapshot.save_failed'))
    }
  }

  private onSnapshotFailed(message: string) {
    console.error('Terminal snapshot capture failed: ' + message)
    showToast(I18n.get('terminal.snapshot.save_failed'))
  }

  private flushPendingOutput() {
    if (this.isReplaying) {
      return
    }
    if (!this.webviewReady) {
      return
    }
    if (this.pendingSwap) {
      this.swapReplayedScreen()
      return
    }
    if (this.pendingBatch.length === 0) {
      return
    }
    this.flushBatch()
  }

  /**
   * Atomically replace the screen with the authoritative replay: the reset
   * wipes the locally cached paint (stale by definition), then the full replay
   * goes in as one write. The cache file is rewritten from the same bytes.
   */
  private swapReplayedScreen() {
    this.pendingSwap = false
    if (this.hasRestoredSnapshot) {
      // The snapshot already paints everything this replay could contain —
      // for a NEW session the authoritative replay is empty, and for a
      // re-opened session it duplicates the snapshot's tail. Resetting here
      // would destroy the concatenated history for nothing. pendingBatch may
      // still hold LIVE output that arrived during the replay window (e.g.
      // the fresh shell banner) — flush it BELOW the restored history.
      console.info('[snapshot] skip reset+replay swap (snapshot restored)')
      this.pendingSwap = false
      this.flushBatch()
      return
    }
    this.runResetTerminal()
    if (this.pendingBatch.length === 0) {
      // Empty authoritative replay — the cached screen must not outlive it.
      TerminalCache.getInstance().clear(this.sessionId)
      return
    }
    const packed = this.pendingBatch.join('|')
    this.pendingBatch = []
    this.flushScheduled = false
    this.writePackedToWebview(packed)
    // A legacy full replay carries no sequence — drop the cursor so the next
    // open falls back to a full replay instead of trusting a stale one.
    TerminalCache.getInstance().replaceAll(this.sessionId, packed)
    TerminalCache.getInstance().clearCursor(this.sessionId)
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

  private onTerminalContextMenu(x: number, y: number) {
    if (x < 0) {
      this.terminalMenuVisible = false
      return
    }
    this.menuX = Math.max(8, Math.min(x - 16, 280))
    this.menuY = y > 160 ? y - 64 : y + 24
    this.webviewController.runJavaScript('hasSelection()')
      .then((r: string) => {
        this.menuHasSelection = r.indexOf('1') >= 0
      })
      .catch(() => {
        this.menuHasSelection = false
      })
    this.terminalMenuVisible = true
  }

  private copyTerminalSelection() {
    this.webviewController.runJavaScript('getSelection()')
      .then((result: string) => {
        let text = result
        try {
          text = JSON.parse(result) as string
        } catch (_e) {}
        if (!text) {
          return
        }
        lightHaptic()
        const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
        pasteboard.getSystemPasteboard().setData(pasteData)
          .then(() => {
            this.webviewController.runJavaScript('clearSelection()')
            this.terminalMenuVisible = false
          })
          .catch((e: Object) => {
            console.error('Failed to copy terminal selection: ' + (e as Error).message)
          })
      })
      .catch((e: Error) => {
        console.error('Failed to read terminal selection: ' + e.message)
      })
  }

  private pasteFromClipboardToTerminal() {
    pasteboard.getSystemPasteboard().getData()
      .then((data: pasteboard.PasteData) => {
        this.pasteTextToTerminal(data.getPrimaryText() ?? '')
      })
      .catch((e: Object) => {
        console.warn('Failed to read pasteboard: ' + (e as Error).message)
      })
  }

  private pasteTextToTerminal(text: string) {
    if (!text) {
      return
    }
    lightHaptic()
    const escaped = text.replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\r')
    try {
      this.webviewController.runJavaScript(`pasteText("${escaped}")`)
        .catch((e: Error) => console.warn('Failed to paste: ' + e.message))
    } catch (e) {
      console.warn('Failed to paste: ' + (e as Error).message)
    }
    this.terminalMenuVisible = false
  }

  @Builder
  TerminalMenuButton(label: string, enabled: boolean, action: () => void) {
    Button(label)
      .height(36)
      .constraintSize({ minWidth: 64 })
      .borderRadius(8)
      .backgroundColor(Color.Transparent)
      .fontColor(enabled ? $r('app.color.terminal_primary') : $r('app.color.terminal_outline'))
      .opacity(enabled ? 1 : 0.5)
      .fontSize(14)
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        if (enabled) {
          action()
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

  private async openFiles() {
    // 会话绑定工作区；旧会话（无 workspaceId）回落到该 worker 的默认工作区。
    const session = await ApiService.getSession(this.sessionId)
    const workspaces = await ApiService.listWorkspaces() as Record<string, Object>[]
    let workspaceId = ''
    let workspaceName = ''
    let fallbackId = ''
    let fallbackName = ''
    for (let i = 0; i < workspaces.length; i++) {
      const item = workspaces[i] as Record<string, Object>
      const id = (item['id'] as string) ?? ''
      const name = (item['name'] as string) ?? ''
      const isDefault = (item['isDefault'] as boolean) ?? false
      if (id.length > 0 && id === session.workspaceId) {
        workspaceId = id
        workspaceName = name
        break
      }
      if (fallbackId.length === 0 && (item['workerId'] as string) === session.workerId) {
        if (isDefault || fallbackName.length === 0) {
          fallbackId = id
          fallbackName = name
        }
      }
    }
    if (workspaceId.length === 0) {
      workspaceId = fallbackId
      workspaceName = fallbackName
    }
    if (workspaceId.length === 0) {
      showToast(I18n.get('workspaces.empty'))
      return
    }
    const param: Record<string, string> = { 'workspaceId': workspaceId, 'workspaceName': workspaceName }
    this.pageStack.pushPath({ name: RouteName.FILES_PAGE, param })
  }
}
