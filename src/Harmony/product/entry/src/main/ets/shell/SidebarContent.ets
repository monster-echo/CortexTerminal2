/**
 * @file SidebarContent.ets
 * @brief Navigation sidebar aligned with the Flutter baseline (design/01 §4).
 *
 * 一级结构：工作区列表（name + worker 在线点 + 会话数，点击进 workspace/Home）
 * →「未分组会话」入口 →「计算机」→「我的」→「+ 新建工作区」（新建工作区流程）。
 */
import { I18n, AuthState, RouteName, ApiService, WorkspaceInfo, WorkerInfo, SessionInfo, lightHaptic, showToast } from '@rwecho/core'
import { NewWorkspaceFlow } from '@rwecho/session'

@Component
export struct SidebarContent {
  activeRoute: string = RouteName.SESSION_HOME
  onNavigate?: (() => void) | null = null
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('userInfo') userInfoSig: string = ''
  @StorageLink('navWorkspaceId') navWorkspaceId: string = ''
  @State workspaces: WorkspaceInfo[] = []
  @State workers: WorkerInfo[] = []
  @State sessions: SessionInfo[] = []
  @State showNewWorkspaceSheet: boolean = false

  aboutToAppear() {
    this.loadData()
  }

  private async loadData() {
    try {
      this.workers = await ApiService.listWorkers()
      this.workspaces = await ApiService.listWorkspaceInfos()
      this.sessions = await ApiService.listSessions()
    } catch (e) {
      // 错误上屏（toast），不吞。
      showToast((e as Error).message)
    }
  }

  /** workerId 与 id 都可能是网关侧主键，任一匹配即可（与首页同规则）。 */
  private onlineOf(workerId: string): boolean {
    for (let i = 0; i < this.workers.length; i++) {
      const w = this.workers[i]
      if (w.workerId === workerId || w.id === workerId) {
        return w.isOnline
      }
    }
    return false
  }

  private sessionCountOf(workspaceId: string): number {
    let count = 0
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].workspaceId === workspaceId) {
        count++
      }
    }
    return count
  }

  private ungroupedCount(): number {
    let count = 0
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].workspaceId.length === 0) {
        count++
      }
    }
    return count
  }

  build() {
    Column() {
      // Brand area
      Row() {
        Image($r('app.media.app_icon'))
          .width(36)
          .height(36)
          .borderRadius(10)

        Column() {
          Text(I18n.get('auth.login.tagline'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_text'))
            .maxLines(1)

          Text('云枢终端')
            .fontSize(11)
            .fontColor($r('app.color.terminal_text_muted'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .height(64)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      // Workspace list + entries（工作区为主结构，design/01 §4）
      Scroll() {
        Column() {
          Text(I18n.get('workspaces.title'))
            .fontSize(12)
            .fontColor($r('app.color.terminal_text_tertiary'))
            .width('100%')
            .padding({ left: 28, top: 8, bottom: 4 })

          ForEach(this.workspaces, (ws: WorkspaceInfo) => {
            this.WorkspaceItem(ws)
          }, (ws: WorkspaceInfo) => ws.id)

          if (this.workspaces.length === 0) {
            Text(I18n.get('sidebar.no_workspaces'))
              .fontSize(13)
              .fontColor($r('app.color.terminal_text_muted'))
              .width('100%')
              .padding({ left: 28, top: 4, bottom: 4 })
          }

          // 未分组会话入口：首页把「未分组」组置顶呈现（收纳区，无新建入口）。
          this.NavItem('⌘', I18n.get('sidebar.ungrouped'), RouteName.SESSION_HOME,
            this.activeRoute === RouteName.SESSION_HOME,
            false,
            `${this.ungroupedCount()}`)

          Divider()
            .color($r('app.color.terminal_border_subtle'))
            .margin({ left: 16, right: 16, top: 10, bottom: 10 })

          // 计算机（worker 列表）
          this.NavItem('▦', I18n.get('sidebar.computers'), RouteName.WORKER_LIST,
            this.activeRoute === RouteName.WORKER_LIST || this.activeRoute === RouteName.WORKER_DETAIL)

          // 扫码激活（对齐 Flutter app_shell：scanLine → /activate，push 压栈）
          this.NavItem('⌖', I18n.get('auth.activate.title'), RouteName.ACTIVATE_WORKER,
            this.activeRoute === RouteName.ACTIVATE_WORKER || this.activeRoute === RouteName.ACTIVATE_CODE,
            true)

          // 我的
          this.NavItem('☺', I18n.get('me.title'), RouteName.SETTINGS,
            this.activeRoute === RouteName.SETTINGS)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // + 新建工作区（对应 Flutter /workspaces/new：电脑→文件夹→名称→创建）
      Button(I18n.get('workspaces.create'))
        .width('calc(100% - 24vp)')
        .height(40)
        .borderRadius(10)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.terminal_text'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .margin({ left: 12, right: 12, bottom: 8 })
        .onClick(() => {
          lightHaptic()
          this.showNewWorkspaceSheet = true
        })

      // User profile
      Row() {
        if (AuthState.getResolvedAvatarUrl().length > 0) {
          Image(AuthState.getResolvedAvatarUrl())
            .width(38)
            .height(38)
            .borderRadius(19)
        } else {
          Text(AuthState.getDisplayName().substring(0, 1).toUpperCase() || 'U')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .borderRadius(19)
        }

        Column() {
          Text(AuthState.getDisplayName() || I18n.get('auth.login.title'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(I18n.get('settings.account'))
            .fontSize(12)
            .fontColor($r('app.color.terminal_text_muted'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.terminal_background_panel'))
      .onClick(() => {
        lightHaptic()
        this.navigate(RouteName.SETTINGS)
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_background_panel'))
    .borderColor($r('app.color.terminal_border_subtle'))
    .borderWidth({ right: 1 })
    .bindSheet($$this.showNewWorkspaceSheet, this.NewWorkspaceSheetContent(), {
      detents: ['80%', SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: true,
      onDisappear: () => { this.showNewWorkspaceSheet = false }
    })
  }

  /** 工作区条目：名称 + worker 在线点 + 会话数；选中态覆盖所属工作区页。 */
  @Builder
  WorkspaceItem(ws: WorkspaceInfo) {
    Row() {
      SymbolGlyph($r('sys.symbol.folder_fill'))
        .fontSize(16)
        .fontColor([$r('app.color.terminal_text_muted')])

      Circle()
        .width(7)
        .height(7)
        .fill(this.onlineOf(ws.workerId) ? $r('app.color.terminal_success') : $r('app.color.terminal_status_idle'))
        .margin({ left: 8 })

      Text(ws.name)
        .fontSize(14)
        .fontWeight(this.isWorkspaceActive(ws) ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.isWorkspaceActive(ws) ? $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 8 })

      Text(`${this.sessionCountOf(ws.id)}`)
        .fontSize(12)
        .fontColor($r('app.color.terminal_text_tertiary'))
    }
    .width('calc(100% - 24vp)')
    .height(44)
    .padding({ left: 10, right: 10 })
    .margin({ left: 12, right: 12, top: 2 })
    .borderRadius(10)
    .backgroundColor(this.isWorkspaceActive(ws) ? $r('app.color.terminal_secondary_container') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      lightHaptic()
      this.openWorkspace(ws)
    })
  }

  /** 选中态含所属工作区页：当前路由是 workspace/Home 且正是该工作区。 */
  private isWorkspaceActive(ws: WorkspaceInfo): boolean {
    return this.activeRoute === RouteName.WORKSPACE_HOME && this.navWorkspaceId === ws.id
  }

  private openWorkspace(ws: WorkspaceInfo) {
    AppStorage.setOrCreate('navWorkspaceId', ws.id)
    AppStorage.setOrCreate('navWorkspaceName', ws.name)
    const param: Record<string, string> = { 'workspaceId': ws.id, 'name': ws.name }
    if (this.onNavigate) {
      this.onNavigate()
    }
    // workspace/Home 是 subPage（AppBar 带返回键）：必须压栈而不是替换，
    // 否则 SESSION_HOME 被顶掉，pop 时栈空 → Navigation 空内容黑屏。
    this.pageStack.pushPath({ name: RouteName.WORKSPACE_HOME, param: param })
  }

  @Builder
  NavItem(icon: string, label: string, route: string, selected: boolean, push: boolean = false,
    count: string = '') {
    Row() {
      Text(icon)
        .fontSize(16)
        .fontColor(selected ? $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_text_muted'))
        .width(28)
        .textAlign(TextAlign.Center)

      Text(label)
        .fontSize(14)
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(selected ? $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_text'))
        .layoutWeight(1)
        .margin({ left: 8 })

      if (count.length > 0) {
        Text(count)
          .fontSize(12)
          .fontColor($r('app.color.terminal_text_tertiary'))
      }
    }
    .width('calc(100% - 24vp)')
    .height(44)
    .padding({ left: 10, right: 10 })
    .margin({ left: 12, right: 12, top: 4 })
    .borderRadius(10)
    .backgroundColor(selected ? $r('app.color.terminal_secondary_container') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      lightHaptic()
      // 扫码页是子页面：push 压栈，返回键才有栈可弹（对齐 Flutter _push）。
      if (push) {
        if (this.onNavigate) {
          this.onNavigate()
        }
        this.pageStack.pushPath({ name: route })
        return
      }
      // 未分组入口：先标记，首页 aboutToAppear 把「未分组」组置顶。
      if (route === RouteName.SESSION_HOME) {
        AppStorage.setOrCreate('focusUngrouped', true)
      }
      this.navigate(route)
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

  private navigate(route: string, param?: Object) {
    if (this.onNavigate) {
      this.onNavigate()
    }
    this.pageStack.replacePath({ name: route, param: param })
  }
}
