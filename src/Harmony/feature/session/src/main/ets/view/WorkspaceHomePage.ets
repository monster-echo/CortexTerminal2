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
  @State workspace: WorkspaceInfo | null = null
  @State sessions: SessionInfo[] = []
  @State workers: WorkerInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @Consume('pageStack') pageStack: NavPathStack

  private workspaceId: string = ''

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
    Scroll() {
      Column() {
        this.InfoCard()
        this.ActionRow()
        this.SessionSection()
      }
      .width('100%')
      // subPage 顶部间距对齐 WorkerDetailPage（区域间距 24），内容不再紧贴 AppBar。
      .padding({ left: 20, right: 20, top: 24, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  InfoCard() {
    Column() {
      Text(this.workspace!.name)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_text'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        Circle()
          .width(10)
          .height(10)
          .fill(this.boundWorker() !== null && this.boundWorker()!.isOnline
            ? $r('app.color.terminal_success')
            : $r('app.color.terminal_status_idle'))
        Text(`${I18n.get('workspace.home.info_worker')}：${this.workerDisplayName()}`)
          .fontSize(13)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ left: 8 })
        Text(this.boundWorker() !== null && this.boundWorker()!.isOnline
          ? I18n.get('workspace.home.status_online')
          : I18n.get('workspace.home.status_offline'))
          .fontSize(12)
          .fontColor($r('app.color.terminal_text_muted'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_background_element'))
          .margin({ left: 8 })
      }
      .margin({ top: 10 })

      if (this.workspace!.rootPath.length > 0) {
        Text(`${I18n.get('workspace.home.info_path')}：${this.workspace!.rootPath}`)
          .fontSize(13)
          .fontColor($r('app.color.terminal_text_muted'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_background_panel'))
  }

  @Builder
  ActionRow() {
    Row({ space: 12 }) {
      // 主操作：黑白反色胶囊（对齐设计规范主按钮）。
      Button(I18n.get('workspace.home.new_session'))
        .height(44)
        .borderRadius(24)
        .backgroundColor($r('app.color.terminal_inverse_surface'))
        .fontColor($r('app.color.terminal_inverse_on_surface'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .enabled(this.boundWorker() !== null && this.boundWorker()!.isOnline)
        .opacity(this.boundWorker() !== null && this.boundWorker()!.isOnline ? 1 : 0.5)
        .onClick(() => { clickHaptic(); this.createSessionInWorkspace() })

      Button(I18n.get('workspace.home.open_files'))
        .height(44)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .onClick(() => { clickHaptic(); this.openFiles() })
    }
    .width('100%')
    .margin({ top: 16 })
  }

  @Builder
  SessionSection() {
    Column() {
      Text(I18n.get('workspace.home.sessions'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.terminal_text'))
        .width('100%')
        .margin({ top: 24, bottom: 12 })

      if (this.sessions.length === 0) {
        Text(I18n.get('workspace.home.empty_sessions'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_text_muted'))
          .width('100%')
      } else {
        ForEach(this.sessions, (session: SessionInfo) => {
          Column() {
            SessionCard({ session: session, onCardClick: () => { lightHaptic(); this.resumeSession(session) } })
          }
          // 长按会话卡片 → 移出工作区（moveSessionToWorkspace 空串 = 移出）。
          .gesture(LongPressGesture({ repeat: false })
            .onAction(() => { this.confirmMoveOut(session) }))
        }, (session: SessionInfo) => session.id)
      }
    }
    .width('100%')
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
    try {
      clickHaptic()
      const request = new SessionCreateRequest()
      request.workerId = this.workspace!.workerId
      request.workspaceId = this.workspace!.id
      const response = await ApiService.createSession(request)
      AnalyticsService.onEvent(AnalyticsEvent.SESSION_CREATE)
      const param = new TerminalNavParam()
      param.sessionId = response.sessionId
      param.sessionName = response.name
      param.workerId = response.workerId
      this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
    } catch (e) {
      showToast((e as Error).message || I18n.get('workspace.home.create_session_failed'))
    }
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
    const all = await ApiService.listSessions()
    const sorted = all.filter((s: SessionInfo) => s.workspaceId === this.workspaceId)
    sorted.sort((a: SessionInfo, b: SessionInfo) => {
      const timeA = new Date(a.updatedAt || a.createdAt).getTime()
      const timeB = new Date(b.updatedAt || b.createdAt).getTime()
      return timeB - timeA
    })
    this.sessions = sorted
  }
}
