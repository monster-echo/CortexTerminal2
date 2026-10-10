import { SessionInfo, WorkspaceInfo, WorkerInfo, ApiService, I18n, RouteName, TerminalNavParam, showI18nToast, showToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic, AppConstants, AnnouncementService, AnnouncementDialog, AnnouncementInfo, TerminalThemeProfile, TerminalThemes } from '@rwecho/core'
import { SessionCard } from './SessionCard'
import { CreateSessionSheet } from './CreateSessionSheet'
import { NewWorkspaceFlow } from './NewWorkspaceFlow'
import { SessionService } from '../service/SessionService'
import { pasteboard } from '@kit.BasicServicesKit'
import { common, Want } from '@kit.AbilityKit'

class TerminalLine {
  type: string = ''
  text: string = ''
  constructor(type: string, text: string) {
    this.type = type
    this.text = text
  }
}

/** 首页会话分组：组头 = 工作区名；workspaceId 空串 = 未分组。 */
@Observed
class SessionGroup {
  workspaceId: string = ''
  title: string = ''
  sessions: SessionInfo[] = []
}

@CustomDialog
struct RenameDialog {
  controller: CustomDialogController
  initialName: string = ''
  @State textInput: string = ''
  onConfirm: (newName: string) => void = () => {}

  aboutToAppear() {
    this.textInput = this.initialName
  }

  build() {
    Column() {
      Text(I18n.get('session.rename_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_text'))
        .margin({ bottom: 16 })

      TextInput({ text: $$this.textInput, placeholder: I18n.get('session.rename_placeholder') })
        .height(48)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_background_element'))
        .fontColor($r('app.color.terminal_text'))
        .placeholderColor($r('app.color.terminal_text_muted'))
        .fontSize(16)
        .selectAll(true)

      Row({ space: 12 }) {
        Button(I18n.get('common.cancel'))
          .height(44)
          .borderRadius(8)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.terminal_text_muted'))
          .border({ width: 1, color: $r('app.color.terminal_border_subtle') })
          .layoutWeight(1)
          .onClick(() => { clickHaptic(); this.controller.close() })

        Button(I18n.get('common.confirm'))
          .height(44)
          .borderRadius(24)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .layoutWeight(1)
          .onClick(() => {
            clickHaptic()
            this.onConfirm(this.textInput.trim())
            this.controller.close()
          })
      }
      .margin({ top: 20 })
    }
    .padding(24)
    .borderRadius(16)
    .backgroundColor($r('app.color.terminal_background_menu'))
    .width('80%')
    .constraintSize({ maxWidth: 320 })
  }
}

@Component
export struct SessionHomePage {
  /** 首页引导块是终端窗口预览，永远用内置 Default Dark 终端档案渲染，不跟随 App 深浅模式。 */
  private guideTheme: TerminalThemeProfile = TerminalThemes.findById('default-dark', [])
  @State allSessions: SessionInfo[] = []
  @State workers: WorkerInfo[] = []
  @State workspaces: WorkspaceInfo[] = []
  @State groups: SessionGroup[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @State showCreateSheet: boolean = false
  @State showNewWorkspaceSheet: boolean = false
  // 侧边栏「未分组会话」入口置位：本次进入把「未分组」组置顶（实现最简方案）。
  @StorageLink('focusUngrouped') focusUngrouped: boolean = false
  private ungroupedFirst: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('triggerCreateSession') @Watch('onCreateTriggered') createTrigger: boolean = false
  private renameDialog: CustomDialogController = new CustomDialogController({
    builder: RenameDialog({ initialName: '', onConfirm: (_n: string) => {} }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  // CustomDialogController 必须是 struct 的成员变量，@CustomDialog 的 controller 才会被注入；
  // 局部变量会导致弹窗里 this.controller 为 undefined，按钮 close() 抛异常、弹窗关不掉。
  private announcementDialog: CustomDialogController = new CustomDialogController({
    builder: AnnouncementDialog({ announcement: new AnnouncementInfo() }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })

  onCreateTriggered() {
    if (this.createTrigger) {
      this.showCreateSheet = true
      this.createTrigger = false
    }
  }

  aboutToAppear() {
    AnalyticsService.onPageStart('session/Home')
    if (this.focusUngrouped) {
      this.ungroupedFirst = true
      this.focusUngrouped = false
    }
    this.loadData()
    this.loadAnnouncement()
  }

  /** 拉取网关公告；弹过一次即记为已读，之后不再弹。 */
  private async loadAnnouncement() {
    const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext
    try {
      const pending = await AnnouncementService.pending(ctx)
      if (pending === null) {
        return
      }
      this.announcementDialog = new CustomDialogController({
        builder: AnnouncementDialog({
          announcement: pending,
          onJoin: (url: string) => {
            this.openExternalUrl(url)
          },
          onDismiss: () => {
            AnnouncementService.dismiss(ctx, pending.id)
          }
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center,
        customStyle: true
      })
      this.announcementDialog.open()
      // 弹出即已读：点按钮、点遮罩、返回键、直接杀进程都不会再弹第二次
      AnnouncementService.dismiss(ctx, pending.id)
    } catch (e) {
      showToast((e as Error).message || I18n.get('announcement.load_failed'))
    }
  }

  /** applink 优先拉起目标 App，未安装时由系统落到浏览器/网页版。 */
  private async openExternalUrl(url: string) {
    const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url
    }
    try {
      await ctx.startAbility(want)
    } catch (e) {
      showToast(I18n.get('common.link_open_failed'))
    }
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
                    .backgroundColor($r('app.color.terminal_background_element'))
                  Row().width(80).height(10).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_background_element'))
                    .margin({ top: 6 })
                  Row().width(60).height(10).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_background_element'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Blank()
                Row().width(48).height(20).borderRadius(8)
                  .backgroundColor($r('app.color.terminal_background_element'))
              }
              .width('100%')
              .height(72)
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_background_panel'))
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
              .fontColor($r('app.color.terminal_text_muted'))
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
        } else if (this.workers.length > 0 && this.workspaces.length === 0) {
          // 零工作区空态：引导创建第一个工作区（会话必须归属工作区）。
          Scroll() {
            Column() {
              Text(I18n.get('session.home.empty_no_workspace'))
                .fontSize(14)
                .fontColor($r('app.color.terminal_text_muted'))
                .textAlign(TextAlign.Center)
                .margin({ top: 48 })

              Button(I18n.get('workspaces.create_first'))
                .width('100%')
                .height(48)
                .borderRadius(24)
                .backgroundColor($r('app.color.terminal_inverse_surface'))
                .fontColor($r('app.color.terminal_inverse_on_surface'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ top: 20 })
                .onClick(() => {
                  clickHaptic()
                  this.showNewWorkspaceSheet = true
                })
            }
            .width('100%')
            .padding({ left: 32, right: 32 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else if (this.workers.length === 0
          || (this.allSessions.length === 0 && this.workspaces.length === 0)) {
          Scroll() {
            Column() {
              if (this.workers.length === 0) {
                this.TerminalGuide()
              } else if (!this.workers.some((w: WorkerInfo) => w.isOnline)) {
                Column() {
                  Text(I18n.get('session.home.empty_active_offline'))
                    .fontSize(14)
                    .fontColor($r('app.color.terminal_text_muted'))
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
            // 工作区为主：每个 workspace 一张卡片（名称 / worker 在线状态 / 会话数）。
            ForEach(this.workspaces, (ws: WorkspaceInfo) => {
              ListItem() {
                this.WorkspaceCard(ws)
              }
            }, (ws: WorkspaceInfo) => ws.id)

            // 未分组分组：无 workspaceId 的会话以「未分组」组头呈现在下方 groups 中。

            // 会话按 workspace 分组：组头 = 工作区名，只显示有会话的组。
            ForEach(this.groups, (group: SessionGroup) => {
              ListItem() {
                Row() {
                  Text(group.title)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.terminal_text_muted'))
                  Blank()
                  Text(I18n.getWithArgs('workspace.home.session_count',
                    this.countArgs(group.sessions.length)))
                    .fontSize(12)
                    .fontColor($r('app.color.terminal_text_tertiary'))
                }
                .width('100%')
                .padding({ left: 4, right: 4, top: 8 })
              }
              ForEach(group.sessions, (session: SessionInfo) => {
                ListItem() {
                  SessionCard({ session: session, onCardClick: () => { lightHaptic(); this.resumeSession(session) } })
                }
                .swipeAction({ end: this.SwipeActions(session) })
              }, (session: SessionInfo) => session.id)
            }, (group: SessionGroup) => group.workspaceId)
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
    .backgroundColor($r('app.color.terminal_background'))
    .bindSheet($$this.showCreateSheet, this.CreateSheetContent(), {
      detents: ['66%', SheetSize.MEDIUM],
      preferType: SheetType.BOTTOM,
      showClose: true,
      onDisappear: () => { this.showCreateSheet = false }
    })
    .bindSheet($$this.showNewWorkspaceSheet, this.NewWorkspaceSheetContent(), {
      detents: ['80%', SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: true,
      onDisappear: () => { this.showNewWorkspaceSheet = false }
    })
  }

  @Builder
  NewWorkspaceSheetContent() {
    Column() {
      NewWorkspaceFlow({
        onCreated: (_workspaceId: string, _workspaceName: string) => {
          this.showNewWorkspaceSheet = false
          this.loadData()
        }
      })
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .width('100%')
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
    .backgroundColor($r('app.color.terminal_background_element'))
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
      .backgroundColor($r('app.color.terminal_background_element'))
      .onClick(() => { clickHaptic(); this.openRenameDialog(session) })

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_error')])
      }
      .width(64)
      .height('100%')
      .borderRadius(12)
      .backgroundColor($r('app.color.terminal_background_element'))
      .onClick(() => { clickHaptic(); this.confirmDelete(session) })
    }
  }

  @Builder
  WorkspaceCard(ws: WorkspaceInfo) {
    Row() {
      SymbolGlyph($r('sys.symbol.folder_fill'))
        .fontSize(22)
        .fontColor([$r('app.color.terminal_secondary')])

      Column() {
        Text(ws.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Circle()
            .width(7)
            .height(7)
            .fill(this.onlineOf(ws.workerId)
              ? $r('app.color.terminal_success')
              : $r('app.color.terminal_status_idle'))
          Text(this.workerName(ws.workerId))
            .fontSize(12)
            .fontColor($r('app.color.terminal_text_muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.onlineOf(ws.workerId)
            ? I18n.get('workspace.home.status_online')
            : I18n.get('workspace.home.status_offline'))
            .fontSize(11)
            .fontColor($r('app.color.terminal_text_muted'))
        }
        .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      Text(I18n.getWithArgs('workspace.home.session_count', this.countArgs(this.sessionCountOf(ws.id))))
        .fontSize(12)
        .fontColor($r('app.color.terminal_text_tertiary'))

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.terminal_text_muted')])
        .margin({ left: 6 })
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_background_panel'))
    // worker 离线：置灰但可见、可进入概览页查看（只有新建等写操作被禁）。
    .opacity(this.onlineOf(ws.workerId) ? 1 : 0.55)
    .onClick(() => { lightHaptic(); this.openWorkspace(ws) })
  }

  @Builder
  CreateSheetContent() {
    CreateSessionSheet({
      showSheet: $showCreateSheet,
      onSessionCreated: (sessionId: string, sessionName: string, workerId: string) => {
        this.showCreateSheet = false
        const param = new TerminalNavParam()
        param.sessionId = sessionId
        param.sessionName = sessionName
        param.workerId = workerId
        this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
      }
    })
  }

  private countArgs(count: number): Record<string, string> {
    const args: Record<string, string> = { 'count': `${count}` }
    return args
  }

  /** workerId 与 id 都可能是网关侧主键，任一匹配即可。 */
  private onlineOf(workerId: string): boolean {
    for (let i = 0; i < this.workers.length; i++) {
      const w = this.workers[i]
      if (w.workerId === workerId || w.id === workerId) {
        return w.isOnline
      }
    }
    return false
  }

  private workerName(workerId: string): string {
    for (let i = 0; i < this.workers.length; i++) {
      const w = this.workers[i]
      if (w.workerId === workerId || w.id === workerId) {
        return w.name || w.hostname || workerId
      }
    }
    return workerId
  }

  private sessionCountOf(workspaceId: string): number {
    let count = 0
    for (let i = 0; i < this.allSessions.length; i++) {
      if (this.allSessions[i].workspaceId === workspaceId) {
        count++
      }
    }
    return count
  }

  private openWorkspace(ws: WorkspaceInfo) {
    // AppBar 标题与侧边栏选中态走 AppStorage（同 navWorkerName 模式）。
    AppStorage.setOrCreate('navWorkspaceId', ws.id)
    AppStorage.setOrCreate('navWorkspaceName', ws.name)
    const param: Record<string, string> = { 'workspaceId': ws.id, 'name': ws.name }
    this.pageStack.pushPath({ name: RouteName.WORKSPACE_HOME, param: param })
  }

  private resumeSession(session: SessionInfo) {
    AnalyticsService.onEvent(AnalyticsEvent.SESSION_RESUME)
    const param = new TerminalNavParam()
    param.sessionId = session.id
    param.sessionName = session.name || 'Terminal'
    param.workerId = session.workerId
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
      this.rebuildGroups()
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
    this.renameDialog = new CustomDialogController({
      builder: RenameDialog({
        initialName: session.name,
        onConfirm: (newName: string) => { this.applyRename(session, newName) }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    })
    this.renameDialog.open()
  }

  private async applyRename(session: SessionInfo, newName: string) {
    if (newName.length === 0 || newName === session.name) {
      return
    }
    try {
      await SessionService.renameSession(session.id, newName)
      this.allSessions = this.allSessions.map((s: SessionInfo): SessionInfo => {
        if (s.id === session.id) {
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
      this.workspaces = await ApiService.listWorkspaceInfos()
      this.rebuildGroups()
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }

  /** 按 workspace 分组（默认工作区在前），无 workspaceId 的会话落到「未分组」组。 */
  private rebuildGroups() {
    const sorted = this.workspaces.slice().sort((a: WorkspaceInfo, b: WorkspaceInfo): number => {
      if (a.isDefault !== b.isDefault) {
        return a.isDefault ? -1 : 1
      }
      return a.name.localeCompare(b.name)
    })
    const groups: SessionGroup[] = []
    for (let i = 0; i < sorted.length; i++) {
      const ws = sorted[i]
      const inWs = this.allSessions.filter((s: SessionInfo) => s.workspaceId === ws.id)
      if (inWs.length === 0) {
        continue
      }
      const group = new SessionGroup()
      group.workspaceId = ws.id
      group.title = ws.name
      group.sessions = inWs
      groups.push(group)
    }
    const ungrouped = this.allSessions.filter((s: SessionInfo) => s.workspaceId.length === 0)
    if (ungrouped.length > 0) {
      const group = new SessionGroup()
      group.workspaceId = ''
      group.title = I18n.get('workspace.home.ungrouped')
      group.sessions = ungrouped
      // 侧边栏「未分组会话」入口进入时置顶该组（收纳区，无新建入口）。
      if (this.ungroupedFirst) {
        groups.unshift(group)
      } else {
        groups.push(group)
      }
    }
    this.groups = groups
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
        new TerminalLine('success', I18n.get('session.home.guide.scan')),
        new TerminalLine('comment', I18n.get('session.home.guide.visit'))
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
          .fontColor(this.guideTheme.brightBlack)
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Divider().color(this.guideTheme.black)

      Column() {
        ForEach(lines, (line: TerminalLine) => {
          if (line.type === 'command') {
            Row() {
              Text('$ ')
                .fontSize(12)
                .fontColor(this.guideTheme.blue)
                .fontFamily('monospace')
              Text(line.text)
                .fontSize(12)
                .fontColor(this.guideTheme.foreground)
                .fontFamily('monospace')
                .layoutWeight(1)
                .copyOption(CopyOptions.InApp)
              Text('📋')
                .fontSize(14)
                .fontColor(this.guideTheme.brightBlack)
                .onClick(() => { this.copyToClipboard(line.text) })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          } else if (line.type === 'comment') {
            Text(line.text)
              .fontSize(12)
              .fontColor(this.guideTheme.brightBlack)
              .fontFamily('monospace')
              .width('100%')
          } else if (line.type === 'success') {
            Text(line.text)
              .fontSize(12)
              .fontColor(this.guideTheme.green)
              .fontFamily('monospace')
              .width('100%')
          } else if (line.type === 'link') {
            Text(line.text)
              .fontSize(12)
              .fontColor(this.guideTheme.blue)
              .fontFamily('monospace')
              .width('100%')
          }
        }, (line: TerminalLine, idx: number) => `${idx}`)
      }
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
    .borderRadius(10)
    .backgroundColor(this.guideTheme.background)
    .clip(true)
  }

  private copyToClipboard(text: string) {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    const systemPasteboard = pasteboard.getSystemPasteboard()
    systemPasteboard.setData(pasteboardData)
    showToast(I18n.get('session.home.guide.copied'))
  }
}
