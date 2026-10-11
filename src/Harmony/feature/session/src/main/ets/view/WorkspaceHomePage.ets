/**
 * @file WorkspaceHomePage.ets
 * @brief 工作区概览页（workspace/Home）。
 *
 * 以工作区为主的信息架构下的一级页面：工作区信息（名称 / worker / 路径）、
 * 该工作区的会话列表（长按移出工作区）、操作入口（新建会话 / 文件）。
 * 路由参数由 push 方传入：{ workspaceId, name }。
 */
import { ApiService, SessionInfo, SessionCreateRequest, WorkspaceInfo, WorkerInfo, I18n, RouteName, TerminalNavParam,
  showI18nToast, showToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic } from '@rwecho/core'
import { SessionCard } from './SessionCard'

@Component
export struct WorkspaceHomePage {
  @StorageLink('language') currentLanguage: string = 'en'
  @StorageLink('workspaceRefreshTick') @Watch('refreshSessions') refreshTick: number = 0
  @StorageLink('triggerWorkspaceSession') @Watch('onCreateTriggered') createTrigger: boolean = false
  @State isCreating: boolean = false
  @State workspace: WorkspaceInfo | null = null
  @State sessions: SessionInfo[] = []
  @State workers: WorkerInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @Consume('pageStack') pageStack: NavPathStack

  private workspaceId: string = ''
  private sessionsRequest: number = 0

  async refreshSessions() {
    if (this.workspaceId.length === 0) return
    try {
      await this.loadSessions()
    } catch (e) {
      showToast((e as Error).message)
    }
  }

  onCreateTriggered() {
    if (this.createTrigger) {
      this.createTrigger = false
      if (this.workspace !== null && this.boundWorker()?.isOnline && !this.isCreating) this.createSessionInWorkspace()
    }
  }

  private tr(key: string): string { return I18n.get(key) + (this.currentLanguage ? '' : '') }

  aboutToAppear() {
    AnalyticsService.onPageStart('workspace/Home')
    const params = this.pageStack.getParamByName(RouteName.WORKSPACE_HOME) as Record<string, string>[]
    // 页面可能被无参重建（如路由恢复）：此时找不到 param，workspaceId 留空走 workspace===null 空态。
    this.workspaceId = params.length > 0 ? (params[params.length - 1]['workspaceId'] as string) : ''
    this.loadData()
  }

  /** worker 在线状态：workerId 与 id 都可能是网关侧主键，任一匹配即可。 */
  private boundWorker(): WorkerInfo | null {
    for (let i = 0; i < this.workers.length; i++) {
      const w = this.workers[i]
      if (w.workerId === this.workspace?.workerId || w.id === this.workspace?.workerId) {
        return w
      }
    }
    return null
  }

  build() {
    Column() {
      Refresh({ refreshing: $$this.isRefreshing }) {
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color($r('app.color.terminal_secondary'))
          }
          .width('100%')
          .margin({ top: 60 })
        } else if (this.errorMessage.length > 0) {
          Column() {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor($r('app.color.terminal_error'))
              .textAlign(TextAlign.Center)
              .padding({ left: 20, right: 20 })

            Button(I18n.get('common.retry'))
              .height(36)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .fontSize(13)
              .margin({ top: 16 })
              .onClick(() => { clickHaptic(); this.loadData() })
          }
          .width('100%')
          .margin({ top: 60 })
        } else if (this.workspace === null) {
          Column() {
            Text(I18n.get('workspaces.empty'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_text_muted'))
          }
          .width('100%')
          .margin({ top: 60 })
        } else {
          this.WorkspaceContent()
        }
      }
      .onRefreshing(() => { this.loadData() })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_background'))
  }

  @Builder
  WorkspaceContent() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          this.InfoCard()
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.folder')).fontSize(22).fontColor([$r('app.color.terminal_text')])
            Text(this.tr('workspace.home.open_files')).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text')).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('app.color.terminal_text_muted')])
          }.width('100%').height(60).padding(16).borderRadius(12)
            .backgroundColor($r('app.color.terminal_background_panel')).border({ width: 1, color: $r('app.color.terminal_border_subtle') })
            .onClick(() => { this.openFiles() })
          this.SessionSection()
        }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 24 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
      Button(this.isCreating ? this.tr('membership.processing') : `＋ ${this.tr('workspace.home.new_session')}`)
        .width('calc(100% - 32vp)').height(48).borderRadius(12).fontSize(16).fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.terminal_inverse_surface')).fontColor($r('app.color.terminal_inverse_on_surface'))
        .enabled(this.boundWorker()?.isOnline === true && !this.isCreating)
        .margin({ left: 16, right: 16, top: 8, bottom: 24 })
        .onClick(() => { this.createSessionInWorkspace() })
    }.width('100%').height('100%')
  }

  @Builder
  InfoCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Circle().width(8).height(8).fill(this.boundWorker()?.isOnline ? $r('app.color.terminal_success') : $r('app.color.terminal_status_idle'))
        Text(`${this.workerDisplayName()} · ${this.tr(this.boundWorker()?.isOnline ? 'workspace.home.status_online' : 'workspace.home.status_offline')}`)
          .fontSize(14).fontColor($r('app.color.terminal_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%')
      Text(this.workspace!.rootPath).fontSize(12).fontFamily('monospace').fontColor($r('app.color.terminal_text_muted'))
        .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').padding({ top: 4, bottom: 4 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  SessionSection() {
    Column({ space: 12 }) {
      Row() {
        Text(this.tr('workspace.home.sessions')).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text')).layoutWeight(1)
        Text(I18n.getWithArgs('workspace.home.session_count', { 'count': `${this.sessions.length}` })).fontSize(12).fontColor($r('app.color.terminal_text_muted'))
      }.width('100%').height(36)
      if (this.sessions.length === 0) {
        Text(this.tr('workspace.home.empty_sessions')).fontSize(14).fontColor($r('app.color.terminal_text_muted')).width('100%').padding({ top: 12, bottom: 12 })
      } else {
        ForEach(this.sessions, (session: SessionInfo) => {
          Column() {
            SessionCard({ session: session, workspaceStyle: true, onCardClick: () => { lightHaptic(); this.resumeSession(session) } })
          }.width('100%').gesture(LongPressGesture({ repeat: false }).onAction(() => { this.confirmMoveOut(session) }))
        }, (session: SessionInfo) => JSON.stringify([session.id, session.name, session.status,
          session.updatedAt, session.lastActivityAt, session.lastActiveAt]))
        Text(this.tr('workspace.ui.move_hint')).fontSize(12).fontColor($r('app.color.terminal_text_muted')).width('100%').margin({ top: 4 })
      }
    }.width('100%')
  }

  private workerDisplayName(): string {
    const worker = this.boundWorker()
    if (worker !== null) {
      return worker.name || worker.hostname || worker.workerId
    }
    return this.workspace !== null ? this.workspace.workerId : ''
  }

  private resumeSession(session: SessionInfo) {
    const param = new TerminalNavParam()
    param.sessionId = session.id
    param.sessionName = session.name || 'Terminal'
    param.workerId = session.workerId
    this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
  }

  private confirmMoveOut(session: SessionInfo) {
    clickHaptic()
    this.getUIContext()?.showAlertDialog({
      title: I18n.get('workspace.home.move_out_confirm_title'),
      message: I18n.get('workspace.home.move_out_confirm_message'),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('workspace.home.move_out'),
        action: () => { this.moveOut(session) }
      }
    })
  }

  private async moveOut(session: SessionInfo) {
    try {
      lightHaptic()
      await ApiService.moveSessionToWorkspace(session.id, '')
      AppStorage.setOrCreate('workspaceRefreshTick', Date.now())
      showI18nToast('workspace.home.move_out_success')
      await this.loadSessions()
    } catch (e) {
      showToast((e as Error).message || I18n.get('workspace.home.move_out_failed'))
    }
  }

  private openFiles() {
    const param: Record<string, string> = {
      'workerId': this.workspace!.workerId,
      'rootDir': this.workspace!.rootPath,
      'workspaceId': this.workspace!.id
    }
    this.pageStack.pushPath({ name: RouteName.FILES_PAGE, param })
  }

  private async createSessionInWorkspace() {
    if (this.isCreating || this.workspace === null || !this.boundWorker()?.isOnline) return
    this.isCreating = true
    try {
      clickHaptic()
      const request = new SessionCreateRequest()
      request.workerId = this.workspace!.workerId
      request.workspaceId = this.workspace!.id
      const response = await ApiService.createSession(request)
      // Keep the created session in the retained page immediately, even when
      // the user returns before the background refresh finishes.
      this.sessionsRequest++
      const created = new SessionInfo()
      created.id = response.sessionId
      created.sessionId = response.sessionId
      created.name = response.name
      created.workerId = response.workerId
      created.workspaceId = this.workspace!.id
      created.status = response.status
      created.createdAt = response.createdAt
      created.updatedAt = response.createdAt
      this.sessions = [created, ...this.sessions.filter((s: SessionInfo) => s.id !== created.id)]
      AppStorage.setOrCreate('workspaceRefreshTick', Date.now())
      AnalyticsService.onEvent(AnalyticsEvent.SESSION_CREATE)
      const param = new TerminalNavParam()
      param.sessionId = response.sessionId
      param.sessionName = response.name
      param.workerId = response.workerId
      this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
    } catch (e) {
      showToast((e as Error).message || I18n.get('workspace.home.create_session_failed'))
    } finally { this.isCreating = false }
  }

  private async loadData() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      this.workers = await ApiService.listWorkers()
      const allWorkspaces = await ApiService.listWorkspaceInfos()
      const found: WorkspaceInfo[] = allWorkspaces.filter((ws: WorkspaceInfo) => ws.id === this.workspaceId)
      // 工作区可能已被删除/不在列表中：置回 null 走空态分支，禁止把 undefined 赋给 @State
      // （undefined !== null 会让渲染走 WorkspaceContent 的 workspace! 强解包 → 渲染期抛异常黑屏）。
      this.workspace = found.length > 0 ? found[0] : null
      await this.loadSessions()
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }

  private async loadSessions() {
    const request = ++this.sessionsRequest
    const all = await ApiService.listSessions()
    if (request !== this.sessionsRequest) return
    const sorted = all.filter((s: SessionInfo) => s.workspaceId === this.workspaceId)
    sorted.sort((a: SessionInfo, b: SessionInfo) => {
      const timeA = new Date(a.updatedAt || a.createdAt).getTime()
      const timeB = new Date(b.updatedAt || b.createdAt).getTime()
      return timeB - timeA
    })
    this.sessions = sorted
  }
}
