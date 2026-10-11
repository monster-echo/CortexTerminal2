import { I18n, AuthState, RouteName, ApiService, WorkspaceInfo, WorkerInfo, SessionInfo, TerminalNavParam, lightHaptic, showToast } from '@rwecho/core'
import { NewWorkspaceFlow } from '@rwecho/session'

@Component
export struct SidebarContent {
  activeRoute: string = RouteName.SESSION_HOME
  onNavigate?: (() => void) | null = null
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('userInfo') userInfoSig: string = ''
  @StorageLink('language') currentLanguage: string = 'en'
  @StorageLink('navWorkspaceId') navWorkspaceId: string = ''
  @StorageLink('sidebarRefreshTick') @Watch('reload') refreshTick: number = 0
  @State workspaces: WorkspaceInfo[] = []
  @State workers: WorkerInfo[] = []
  @State sessions: SessionInfo[] = []
  @State expandedId: string = ''
  @State showNewWorkspaceSheet: boolean = false

  aboutToAppear() { this.expandedId = this.navWorkspaceId; this.loadData() }
  reload() { this.expandedId = this.navWorkspaceId; this.loadData() }
  private tr(key: string): string { return I18n.get(key) + (this.currentLanguage ? '' : '') }
  private async loadData() {
    try {
      this.workers = await ApiService.listWorkers()
      this.workspaces = await ApiService.listWorkspaceInfos()
      this.sessions = await ApiService.listSessions()
    } catch (e) { showToast((e as Error).message) }
  }
  private sessionsFor(id: string): SessionInfo[] {
    return this.sessions.filter((s: SessionInfo) => s.workspaceId === id)
      .sort((a: SessionInfo, b: SessionInfo): number => new Date(b.updatedAt || b.createdAt).getTime() - new Date(a.updatedAt || a.createdAt).getTime())
  }
  private close() { if (this.onNavigate) this.onNavigate() }
  private push(route: string) {
    lightHaptic(); this.close()
    if (this.activeRoute === route) return
    if (route === RouteName.WORKER_LIST) {
      const param: Record<string, string> = { 'from': 'workspace' }
      this.pageStack.pushPath({ name: route, param })
    } else { this.pageStack.pushPath({ name: route }) }
  }
  private goHome() {
    lightHaptic(); this.close()
    if (this.activeRoute !== RouteName.SESSION_HOME) this.pageStack.popToName(RouteName.SESSION_HOME)
  }
  private openWorkspace(ws: WorkspaceInfo) {
    lightHaptic(); this.close()
    AppStorage.setOrCreate('navWorkspaceId', ws.id)
    AppStorage.setOrCreate('navWorkspaceName', ws.name)
    const param: Record<string, string> = { 'workspaceId': ws.id, 'name': ws.name }
    if (this.activeRoute === RouteName.WORKSPACE_HOME) this.pageStack.replacePath({ name: RouteName.WORKSPACE_HOME, param })
    else this.pageStack.pushPath({ name: RouteName.WORKSPACE_HOME, param })
  }
  private openSession(session: SessionInfo) {
    this.close()
    const param = new TerminalNavParam()
    param.sessionId = session.id; param.sessionName = session.name; param.workerId = session.workerId
    this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param })
  }
  private active(ws: WorkspaceInfo): boolean { return this.activeRoute === RouteName.WORKSPACE_HOME && this.navWorkspaceId === ws.id }
  private running(s: SessionInfo): boolean { return ['running', 'live', 'connected'].includes(s.status.toLowerCase()) }

  build() {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.app_icon')).width(30).height(30).borderRadius(8)
        Text(this.tr('workspace.ui.brand')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.terminal_text'))
      }.width('100%').height(64).padding({ left: 20, right: 16 })
      Scroll() {
        Column({ space: 4 }) {
          this.NavRow($r('app.media.ws_grid'), this.tr('workspaces.title'), '', this.activeRoute === RouteName.SESSION_HOME, () => { this.goHome() })
          this.NavRow($r('app.media.ws_terminal'), this.tr('workspace.home.ungrouped'), 'ungrouped', this.activeRoute === RouteName.UNGROUPED, () => { this.push(RouteName.UNGROUPED) })
          Divider().color($r('app.color.terminal_border_subtle')).margin({ top: 12, bottom: 12 })
          Row() {
            Text(this.tr('workspaces.title')).fontSize(13).fontColor($r('app.color.terminal_text_muted')).layoutWeight(1)
            Button() { SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([$r('app.color.terminal_text')]) }
              .width(44).height(44).padding(0).backgroundColor(Color.Transparent)
              .accessibilityText(this.tr('workspaces.create')).onClick(() => { this.showNewWorkspaceSheet = true })
          }.width('100%').height(44).padding({ left: 8 })
          ForEach(this.workspaces, (ws: WorkspaceInfo) => {
            this.WorkspaceRow(ws)
            if (this.expandedId === ws.id) {
              ForEach(this.sessionsFor(ws.id), (session: SessionInfo) => { this.SessionRow(session) },
                (session: SessionInfo) => JSON.stringify([session.id, session.name, session.status]))
              if (this.sessionsFor(ws.id).length === 0) {
                Text(this.tr('workspace.home.empty_sessions')).fontSize(12).fontColor($r('app.color.terminal_text_muted'))
                  .width('100%').padding({ left: 40, top: 8, bottom: 8 })
              }
            }
          }, (ws: WorkspaceInfo) => ws.id)
          if (this.workspaces.length === 0) {
            Text(this.tr('sidebar.no_workspaces')).fontSize(13).fontColor($r('app.color.terminal_text_muted')).padding(12)
          }
          Divider().color($r('app.color.terminal_border_subtle')).margin({ top: 16, bottom: 12 })
          this.NavRow($r('app.media.ws_computer'), this.tr('sidebar.computers'), 'workers', false, () => { this.push(RouteName.WORKER_LIST) })
          this.NavRow($r('app.media.ws_scan'), this.tr('workspace.ui.connect'), '', false, () => { this.push(RouteName.ACTIVATE_WORKER) })
        }.width('100%').padding({ left: 12, right: 12, bottom: 16 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
      Divider().color($r('app.color.terminal_border_subtle'))
      Row({ space: 10 }) {
        if (AuthState.getResolvedAvatarUrl().length > 0) {
          Image(AuthState.getResolvedAvatarUrl()).width(40).height(40).borderRadius(20)
        } else {
          Text(AuthState.getDisplayName().substring(0, 1).toUpperCase() || 'U').width(40).height(40).textAlign(TextAlign.Center)
            .fontSize(16).fontColor($r('app.color.terminal_on_secondary_container')).backgroundColor($r('app.color.terminal_secondary_container')).borderRadius(20)
        }
        Column({ space: 3 }) {
          Text(AuthState.getDisplayName()).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text'))
          Text(this.tr('workspace.ui.profile')).fontSize(11).fontColor($r('app.color.terminal_text_muted'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('app.color.terminal_text_muted')])
      }.width('100%').height(80).padding({ left: 20, right: 20 }).onClick(() => { this.push(RouteName.SETTINGS) })
    }.width('100%').height('100%').backgroundColor($r('app.color.terminal_background_panel'))
      .border({ width: { right: 1 }, color: $r('app.color.terminal_border_subtle') })
      .bindSheet($$this.showNewWorkspaceSheet, this.NewWorkspaceSheetContent(), {
        detents: ['80%', SheetSize.LARGE], preferType: SheetType.BOTTOM, showClose: true,
        backgroundColor: $r('app.color.terminal_background'), onDisappear: () => { this.showNewWorkspaceSheet = false }
      })
  }

  @Builder
  NavRow(icon: Resource, label: string, count: string, selected: boolean, action: () => void) {
    Row({ space: 12 }) {
      Image(icon).width(22).height(22).fillColor($r('app.color.terminal_text'))
      Text(label).fontSize(14).fontWeight(selected ? FontWeight.Medium : FontWeight.Normal).fontColor($r('app.color.terminal_text')).layoutWeight(1)
      if (count.length > 0) { Text(`${count === 'workers' ? this.workers.length : this.sessionsFor('').length}`).fontSize(12).fontColor($r('app.color.terminal_text_muted')) }
      if (!selected) { SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('app.color.terminal_text_muted')]) }
    }.width('100%').height(48).padding({ left: 12, right: 12 }).borderRadius(10)
      .backgroundColor(selected ? $r('app.color.terminal_secondary_container') : Color.Transparent).onClick(action)
  }

  @Builder
  WorkspaceRow(ws: WorkspaceInfo) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.folder')).fontSize(20).fontColor([$r('app.color.terminal_text')])
      Text(ws.name).fontSize(14).fontColor($r('app.color.terminal_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1).onClick(() => { this.openWorkspace(ws) })
      Button() {
        SymbolGlyph(this.expandedId === ws.id ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(12).fontColor([$r('app.color.terminal_text_muted')])
      }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText(this.tr('workspace.ui.expand'))
        .onClick(() => { this.expandedId = this.expandedId === ws.id ? '' : ws.id })
    }.width('100%').height(44).padding({ left: 12 }).borderRadius(10)
      .backgroundColor(this.active(ws) ? $r('app.color.terminal_secondary_container') : Color.Transparent)
  }

  @Builder
  SessionRow(session: SessionInfo) {
    Row({ space: 8 }) {
      Image($r('app.media.ws_terminal')).width(15).height(15).fillColor($r('app.color.terminal_text_muted'))
      Text(session.name || session.id.substring(0, 8)).fontSize(12).fontColor($r('app.color.terminal_text')).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Circle().width(6).height(6).fill(this.running(session) ? $r('app.color.terminal_success') : $r('app.color.terminal_status_idle'))
      Text(this.tr(this.running(session) ? 'workspace.ui.running' : 'workspace.ui.idle')).fontSize(10).fontColor($r('app.color.terminal_text_muted'))
    }.width('100%').height(40).padding({ left: 36, right: 12 }).onClick(() => { this.openSession(session) })
  }

  @Builder
  NewWorkspaceSheetContent() {
    Column() {
      NewWorkspaceFlow({ onCreated: (_id: string, _name: string) => {
        this.showNewWorkspaceSheet = false
        AppStorage.setOrCreate('workspaceRefreshTick', Date.now())
        this.loadData()
      } })
    }.width('100%').padding(20)
  }
}
