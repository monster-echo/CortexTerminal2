import { SessionInfo, WorkerInfo, I18n, RouteName, TerminalNavParam, showI18nToast, showToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic, AppConstants } from '@rwecho/core'
import { SessionCard } from './SessionCard'
import { CreateSessionSheet } from './CreateSessionSheet'
import { SessionService } from '../service/SessionService'
import { pasteboard } from '@kit.BasicServicesKit'

class TerminalLine {
  type: string = ''
  text: string = ''
  constructor(type: string, text: string) {
    this.type = type
    this.text = text
  }
}

@Component
export struct SessionHomePage {
  @State allSessions: SessionInfo[] = []
  @State workers: WorkerInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @State showCreateSheet: boolean = false
  @State showRenameDialog: boolean = false
  @State renameTarget: SessionInfo = new SessionInfo()
  @State renameInput: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('triggerCreateSession') @Watch('onCreateTriggered') createTrigger: boolean = false

  onCreateTriggered() {
    if (this.createTrigger) {
      this.showCreateSheet = true
      this.createTrigger = false
    }
  }

  aboutToAppear() {
    AnalyticsService.onPageStart('session/Home')
    this.loadData()
  }

  build() {
    Column() {
      Refresh({ refreshing: $$this.isRefreshing }) {
        if (this.isLoading) {
          Column() {
            ForEach([0, 1, 2], (_: number, idx: number) => {
              Row() {
                Column() {
                  Row().width(120).height(14).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_surface_container_high'))
                  Row().width(80).height(10).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_surface_container_high'))
                    .margin({ top: 6 })
                  Row().width(60).height(10).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_surface_container_high'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Blank()
                Row().width(48).height(20).borderRadius(8)
                  .backgroundColor($r('app.color.terminal_surface_container_high'))
              }
              .width('100%')
              .height(72)
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_surface_container'))
              .margin({ bottom: 8 })
            }, (_: number, idx: number) => `${idx}`)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8 })
        } else if (this.errorMessage.length > 0) {
          Column() {
            Text(I18n.get('common.error'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_error'))
              .margin({ top: 40 })

            Text(this.errorMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .textAlign(TextAlign.Center)
              .margin({ top: 8 })
              .padding({ left: 28, right: 28 })

            Button(I18n.get('common.retry'))
              .height(44)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .margin({ top: 16 })
              .onClick(() => { clickHaptic(); this.loadData() })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 20, right: 20 })
        } else if (this.allSessions.length === 0) {
          Scroll() {
            Column() {
              if (this.workers.length === 0) {
                this.TerminalGuide()
              } else if (!this.workers.some((w: WorkerInfo) => w.isOnline)) {
                Column() {
                  Text(I18n.get('session.home.empty_active_offline'))
                    .fontSize(14)
                    .fontColor($r('app.color.terminal_on_surface_variant'))
                }
                .margin({ top: 40 })
              } else {
                Column() {
                  Text(I18n.get('session.home.empty_active_online'))
                    .fontSize(14)
                    .fontColor($r('app.color.terminal_secondary'))
                }
                .margin({ top: 40 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else {
          List({ space: 8 }) {
            ForEach(this.allSessions, (session: SessionInfo) => {
              ListItem() {
                SessionCard({ session: session })
              }
              .swipeAction({ end: this.SwipeActions(session) })
              .onClick(() => { lightHaptic(); this.resumeSession(session) })
            }, (session: SessionInfo) => session.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20, right: 20, top: 8 })
        }
      }
      .onRefreshing(() => { this.loadData() })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_surface'))
    .bindSheet($$this.showCreateSheet, this.CreateSheetContent(), {
      height: SheetSize.LARGE,
      showClose: true,
      onDisappear: () => { this.showCreateSheet = false }
    })
    .bindContentCover($$this.showRenameDialog, this.RenameDialogContent(), {
      modalTransition: ModalTransition.NONE
    })
  }

  @Builder
  DeleteSwipeButton(session: SessionInfo) {
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([$r('app.color.terminal_error')])
    }
    .width(64)
    .height('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .onClick(() => { clickHaptic(); this.confirmDelete(session) })
  }

  @Builder
  SwipeActions(session: SessionInfo) {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.pencil_line_1'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_secondary')])
      }
      .width(64)
      .height('100%')
      .borderRadius(12)
      .backgroundColor($r('app.color.terminal_surface_container_high'))
      .onClick(() => { clickHaptic(); this.openRenameDialog(session) })

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_error')])
      }
      .width(64)
      .height('100%')
      .borderRadius(12)
      .backgroundColor($r('app.color.terminal_surface_container_high'))
      .onClick(() => { clickHaptic(); this.confirmDelete(session) })
    }
  }

  @Builder
  RenameDialogContent() {
    Column() {
      Column() {
        Text(I18n.get('session.rename_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .margin({ bottom: 16 })

        TextInput({ text: $$this.renameInput, placeholder: I18n.get('session.rename_placeholder') })
          .height(48)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .fontColor($r('app.color.terminal_primary'))
          .placeholderColor($r('app.color.terminal_on_surface_variant'))
          .fontSize(16)
          .selectAll(true)

        Row({ space: 12 }) {
          Button(I18n.get('common.cancel'))
            .height(44)
            .borderRadius(8)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .border({ width: 1, color: $r('app.color.terminal_outline_variant') })
            .layoutWeight(1)
            .onClick(() => { this.showRenameDialog = false })

          Button(I18n.get('common.confirm'))
            .height(44)
            .borderRadius(24)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .layoutWeight(1)
            .onClick(() => { this.confirmRename() })
        }
        .margin({ top: 20 })
      }
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.terminal_surface_container_highest'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
    .padding({ left: 32, right: 32 })
    .onClick(() => { this.showRenameDialog = false })
  }

  @Builder
  CreateSheetContent() {
    CreateSessionSheet({
      onSessionCreated: (sessionId: string, sessionName: string) => {
        this.showCreateSheet = false
        const param = new TerminalNavParam()
        param.sessionId = sessionId
        param.sessionName = sessionName
        this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
      }
    })
  }

  private resumeSession(session: SessionInfo) {
    AnalyticsService.onEvent(AnalyticsEvent.SESSION_RESUME)
    const param = new TerminalNavParam()
    param.sessionId = session.id
    param.sessionName = session.name || 'Terminal'
    this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
  }

  private confirmDelete(session: SessionInfo) {
    this.getUIContext()?.showAlertDialog({
      title: I18n.get('session.card.delete_confirm_title'),
      message: I18n.get('session.card.delete_confirm_message'),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('common.delete'),
        fontColor: $r('app.color.terminal_error'),
        action: () => { this.deleteSession(session) }
      }
    })
  }

  private async deleteSession(session: SessionInfo) {
    try {
      await SessionService.deleteSession(session.id)
      this.allSessions = this.allSessions.filter(s => s.id !== session.id)
      AnalyticsService.onEvent(AnalyticsEvent.SESSION_DELETE)
      showI18nToast('session.deleted')
    } catch (e) {
      this.getUIContext()?.showAlertDialog({
        title: I18n.get('common.error'),
        message: (e as Error).message,
        confirm: { value: I18n.get('common.confirm'), action: () => {} }
      })
    }
  }

  private openRenameDialog(session: SessionInfo) {
    this.renameTarget = session
    this.renameInput = session.name
    this.showRenameDialog = true
  }

  private async confirmRename() {
    const newName = this.renameInput.trim()
    if (newName.length === 0 || newName === this.renameTarget.name) {
      this.showRenameDialog = false
      return
    }
    try {
      await SessionService.renameSession(this.renameTarget.id, newName)
      this.allSessions = this.allSessions.map((s: SessionInfo): SessionInfo => {
        if (s.id === this.renameTarget.id) {
          const updated = new SessionInfo()
          updated.id = s.id
          updated.sessionId = s.sessionId
          updated.name = newName
          updated.status = s.status
          updated.workerId = s.workerId
          updated.workerName = s.workerName
          updated.createdAt = s.createdAt
          updated.updatedAt = s.updatedAt
          updated.lastActivityAt = s.lastActivityAt
          updated.lastActiveAt = s.lastActiveAt
          updated.columns = s.columns
          updated.rows = s.rows
          return updated
        }
        return s
      })
      showI18nToast('session.renamed')
    } catch (e) {
      this.getUIContext()?.showAlertDialog({
        title: I18n.get('common.error'),
        message: (e as Error).message,
        confirm: { value: I18n.get('common.confirm'), action: () => {} }
      })
    }
    this.showRenameDialog = false
  }

  private async loadData() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      const data = await SessionService.loadHomeData()
      const all = data.activeSessions.concat(data.historySessions)
      all.sort((a: SessionInfo, b: SessionInfo) => {
        const timeA = new Date(a.updatedAt || a.createdAt).getTime()
        const timeB = new Date(b.updatedAt || b.createdAt).getTime()
        return timeB - timeA
      })
      this.allSessions = all
      this.workers = data.workers
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }

  // ── Terminal Install Guide ─────────────────────────────────────

  @Builder
  TerminalGuide() {
    Column({ space: 12 }) {
      this.TerminalBlock(I18n.get('session.home.guide.title'), [
        new TerminalLine('comment', I18n.get('session.home.guide.no_session')),
        new TerminalLine('comment', I18n.get('session.home.guide.need_worker')),
        new TerminalLine('success', I18n.get('session.home.guide.follow_steps'))
      ])

      this.TerminalBlock(I18n.get('session.home.guide.step1_mac'), [
        new TerminalLine('command', 'curl -fsSL https://corterm.rwecho.top/install.sh | sh')
      ])

      this.TerminalBlock(I18n.get('session.home.guide.step1_win'), [
        new TerminalLine('command', 'powershell -Command "irm https://corterm.rwecho.top/install.ps1 | iex"')
      ])

      this.TerminalBlock(I18n.get('session.home.guide.step2_activate'), [
        new TerminalLine('comment', I18n.get('session.home.guide.auto_activate')),
        new TerminalLine('link', I18n.get('session.home.guide.visit'))
      ])

      // Activate button
      Button(I18n.get('session.home.guide.enter_code'))
        .width('100%')
        .height(44)
        .borderRadius(10)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          clickHaptic()
          this.pageStack.pushPath({ name: RouteName.ACTIVATE_WORKER })
        })

      this.TerminalBlock(I18n.get('session.home.guide.step3_start'), [
        new TerminalLine('comment', I18n.get('session.home.guide.back_refresh')),
        new TerminalLine('comment', I18n.get('session.home.guide.create_session')),
        new TerminalLine('success', I18n.get('session.home.guide.ready'))
      ])
    }
  }

  @Builder
  TerminalBlock(title: string, lines: TerminalLine[]) {
    Column() {
      Row() {
        Row().width(8).height(8).borderRadius(4).backgroundColor('#ff5f57')
        Row().width(8).height(8).borderRadius(4).backgroundColor('#febc2e').margin({ left: 6 })
        Row().width(8).height(8).borderRadius(4).backgroundColor('#28c840').margin({ left: 6 })
        Text(title)
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Divider().color('#21262d')

      Column() {
        ForEach(lines, (line: TerminalLine) => {
          if (line.type === 'command') {
            Row() {
              Text('$ ')
                .fontSize(12)
                .fontColor('#58a6ff')
                .fontFamily('monospace')
              Text(line.text)
                .fontSize(12)
                .fontColor('#c9d1d9')
                .fontFamily('monospace')
                .layoutWeight(1)
                .copyOption(CopyOptions.InApp)
              Text('📋')
                .fontSize(14)
                .fontColor($r('app.color.terminal_on_surface_variant'))
                .onClick(() => { this.copyToClipboard(line.text) })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          } else if (line.type === 'comment') {
            Text(line.text)
              .fontSize(12)
              .fontColor('#8b949e')
              .fontFamily('monospace')
              .width('100%')
          } else if (line.type === 'success') {
            Text(line.text)
              .fontSize(12)
              .fontColor('#3fb950')
              .fontFamily('monospace')
              .width('100%')
          } else if (line.type === 'link') {
            Text(line.text)
              .fontSize(12)
              .fontColor('#58a6ff')
              .fontFamily('monospace')
              .width('100%')
          }
        }, (line: TerminalLine, idx: number) => `${idx}`)
      }
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
    .borderRadius(10)
    .backgroundColor('#0d1117')
    .clip(true)
  }

  private copyToClipboard(text: string) {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    const systemPasteboard = pasteboard.getSystemPasteboard()
    systemPasteboard.setData(pasteboardData)
    showToast(I18n.get('session.home.guide.copied'))
  }
}
