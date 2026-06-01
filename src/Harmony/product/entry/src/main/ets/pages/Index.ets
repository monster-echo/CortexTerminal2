/**
 * @file Index.ets
 * @brief Main Navigation shell with adaptive sidebar
 */
import { display } from '@kit.ArkUI'
import { AuthComponent, AuthService, PasswordLoginPage } from '@rwecho/auth'
import { RestApiClient, SessionCreateRequest, SessionInfo, TerminalHome, TerminalPage } from '@rwecho/terminal'
import { WorkerDetailPage, WorkerListPage } from '@rwecho/worker'
import { SettingsPage } from '@rwecho/settings'
import { WorkerInfo } from '@rwecho/core'

const ROUTE_AUTH = 'Auth'
const ROUTE_PASSWORD_LOGIN = 'PasswordLogin'
const ROUTE_TERMINAL_HOME = 'TerminalHome'
const ROUTE_TERMINAL_SESSION = 'TerminalSession'
const ROUTE_WORKERS = 'Workers'
const ROUTE_WORKER_DETAIL = 'WorkerDetail'
const ROUTE_SETTINGS = 'Settings'

@Entry
@Component
struct Index {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack()
  @StorageLink('authToken') @Watch('onAuthChanged') authToken: string = ''
  @StorageLink('isLoggedIn') @Watch('onAuthChanged') isLoggedIn: boolean = false
  private authService: AuthService = new AuthService()
  private isInitialized: boolean = false

  aboutToAppear() {
    console.info(`[Index] aboutToAppear: isLoggedIn=${this.isLoggedIn}, authToken=${this.authToken.length > 0 ? 'present' : 'empty'}`)
    if (this.isLoggedIn && this.authToken && this.authToken.length > 0) {
      this.pageStack.replacePath({ name: ROUTE_TERMINAL_HOME })
      this.validateStoredToken()
    } else {
      this.pageStack.replacePath({ name: ROUTE_AUTH })
    }
    this.isInitialized = true
  }

  onAuthChanged() {
    if (!this.isInitialized) {
      return
    }
    console.info(`[Index] Auth state changed: isLoggedIn=${this.isLoggedIn}, hasToken=${this.authToken.length > 0}`)
    if (!this.isLoggedIn || this.authToken.length === 0) {
      this.pageStack.replacePath({ name: ROUTE_AUTH })
    }
  }

  private async validateStoredToken() {
    const valid = await this.authService.ensureAuthenticated()
    if (!valid) {
      console.warn('[Index] Stored token is invalid and refresh failed, redirecting to login')
      this.authToken = ''
      this.isLoggedIn = false
      this.pageStack.replacePath({ name: ROUTE_AUTH })
    } else {
      console.info('[Index] Stored token is valid')
    }
  }

  build() {
    Navigation(this.pageStack) {
      Column()
        .width('100%')
        .height('100%')
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === ROUTE_AUTH) {
      AuthComponent()
    } else if (name === ROUTE_PASSWORD_LOGIN) {
      PasswordLoginPage()
    } else if (name === ROUTE_TERMINAL_HOME) {
      NavDestination() {
        ShellScaffold({ activeRoute: ROUTE_TERMINAL_HOME })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === ROUTE_TERMINAL_SESSION) {
      NavDestination() {
        ShellScaffold({ activeRoute: ROUTE_TERMINAL_SESSION })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === ROUTE_WORKERS) {
      NavDestination() {
        ShellScaffold({ activeRoute: ROUTE_WORKERS })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === ROUTE_WORKER_DETAIL) {
      NavDestination() {
        ShellScaffold({ activeRoute: ROUTE_WORKER_DETAIL })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === ROUTE_SETTINGS) {
      NavDestination() {
        ShellScaffold({ activeRoute: ROUTE_SETTINGS })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    }
  }
}

@Component
struct ShellScaffold {
  activeRoute: string = ROUTE_TERMINAL_HOME
  @Consume('pageStack') pageStack: NavPathStack
  @State isWide: boolean = false
  @State sidebarOpen: boolean = false
  @State isCreatingSession: boolean = false
  @State showCreateModal: boolean = false
  @State modalWorkers: WorkerInfo[] = []
  @State isModalLoading: boolean = false
  private apiClient: RestApiClient = new RestApiClient()

  aboutToAppear() {
    console.info('[ShellScaffold] aboutToAppear route=' + this.activeRoute)
  }

  onBackPress(): boolean {
    if (this.sidebarOpen && !this.isWide) {
      this.sidebarOpen = false
      return true
    }
    return false
  }

  build() {
    SideBarContainer(SideBarContainerType.Overlay) {
      // First child: sidebar content
      SidebarContent({
        activeRoute: this.activeRoute,
        onNavigate: () => { this.sidebarOpen = false }
      })

      // Second child: main content
      Column() {
        // AppBar
        if (this.activeRoute !== ROUTE_TERMINAL_SESSION &&
          this.activeRoute !== ROUTE_WORKER_DETAIL) {
          this.AppBar()
        }

        // Page content
        this.ActivePage()
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showCreateModal, this.CreateSessionSheet(), {
        height: SheetSize.LARGE,
        showClose: true,
        onDisappear: () => { this.showCreateModal = false }
      })
    }
    .showSideBar(this.sidebarOpen)
    .showControlButton(false)
    .sideBarWidth(304)
    .autoHide(true)
    .onChange((value: boolean) => {
      this.sidebarOpen = value
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  AppBar() {
    Row() {
      // Left: hamburger (home) or back button (sub-pages)
      if (this.activeRoute === ROUTE_TERMINAL_HOME) {
        Button() {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.sidebarOpen = !this.sidebarOpen
        })
      } else {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.pageStack.replacePath({ name: ROUTE_TERMINAL_HOME })
        })
      }

      // Center: page title
      Text(this.pageTitle())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .layoutWeight(1)
        .margin({ left: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // Right: page-specific actions
      if (this.activeRoute === ROUTE_TERMINAL_HOME) {
        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openCreateModal()
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ActivePage() {
    if (this.activeRoute === ROUTE_TERMINAL_HOME) {
      TerminalHome()
    } else if (this.activeRoute === ROUTE_TERMINAL_SESSION) {
      TerminalPage()
    } else if (this.activeRoute === ROUTE_WORKERS) {
      WorkerListPage()
    } else if (this.activeRoute === ROUTE_WORKER_DETAIL) {
      WorkerDetailPage()
    } else if (this.activeRoute === ROUTE_SETTINGS) {
      SettingsPage()
    } else {
      TerminalHome()
    }
  }

  private pageTitle(): string {
    switch (this.activeRoute) {
      case ROUTE_TERMINAL_HOME:
        return '终端会话'
      case ROUTE_WORKERS:
        return 'Workers'
      case ROUTE_SETTINGS:
        return '设置'
      default:
        return ''
    }
  }

  private openCreateModal() {
    this.loadWorkersForModal()
    this.showCreateModal = true
  }

  private async loadWorkersForModal() {
    this.isModalLoading = true
    try {
      this.modalWorkers = await this.apiClient.listWorkers()
    } catch (e) {
      this.modalWorkers = []
    } finally {
      this.isModalLoading = false
    }
  }

  private calculateTerminalSize(): { cols: number, rows: number } {
    try {
      const disp = display.getDefaultDisplaySync()
      const vpWidth = px2vp(disp.width)
      const vpHeight = px2vp(disp.height)
      const fontSize = 14
      const charWidth = fontSize * 0.602
      const charHeight = fontSize * 1.2
      const topBarHeight = 52 + 28
      const keyBarHeight = 52
      const cols = Math.floor(vpWidth / charWidth)
      const rows = Math.floor((vpHeight - topBarHeight - keyBarHeight) / charHeight)
      return { cols: Math.max(cols, 20), rows: Math.max(rows, 6) }
    } catch (e) {
      return { cols: 80, rows: 24 }
    }
  }

  private async createSessionOnWorker(workerId: string) {
    if (this.isCreatingSession) {
      return
    }
    this.isCreatingSession = true
    try {
      const size = this.calculateTerminalSize()
      const request = new SessionCreateRequest()
      request.columns = size.cols
      request.rows = size.rows
      request.workerId = workerId
      AppStorage.setOrCreate('terminalCols', size.cols)
      AppStorage.setOrCreate('terminalRows', size.rows)
      const session = await this.apiClient.createSession(request)
      AppStorage.setOrCreate('navSessionId', session.id)
      AppStorage.setOrCreate('navSessionName', session.name)
      this.showCreateModal = false
      this.pageStack.pushPath({ name: ROUTE_TERMINAL_SESSION })
    } catch (e) {
      console.error('Failed to create session: ' + (e as Error).message)
    } finally {
      this.isCreatingSession = false
    }
  }

  @Builder
  CreateSessionSheet() {
    Column() {
      Text('选择 Worker 创建终端')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .width('100%')
        .margin({ bottom: 16 })

      if (this.isModalLoading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.terminal_secondary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 24 })
      } else {
        if (this.modalWorkers.filter(w => w.isOnline).length === 0) {
          Column() {
            Text('暂无在线 Worker')
              .fontSize(15)
              .fontColor($r('app.color.terminal_on_surface_variant'))
            Text('请先启动 Worker 节点')
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 24 })
        } else {
          List() {
            ForEach(this.modalWorkers.filter(w => w.isOnline), (worker: WorkerInfo) => {
              ListItem() {
                Row() {
                  Circle()
                    .width(10)
                    .height(10)
                    .fill($r('app.color.terminal_tertiary'))
                    .margin({ right: 12 })

                  Column() {
                    Text(worker.name || worker.hostname || 'Unknown')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.terminal_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(worker.os || worker.operatingSystem || '')
                      .fontSize(12)
                      .fontColor($r('app.color.terminal_on_surface_variant'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Button('创建')
                    .height(32)
                    .borderRadius(8)
                    .backgroundColor($r('app.color.terminal_secondary_container'))
                    .fontColor($r('app.color.terminal_on_secondary_container'))
                    .fontSize(13)
                    .onClick(() => {
                      this.createSessionOnWorker(worker.id)
                    })
                }
                .width('100%')
                .height(60)
                .alignItems(VerticalAlign.Center)
              }
            }, (worker: WorkerInfo) => worker.id)
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 1, color: $r('app.color.terminal_outline_variant'), startMargin: 0, endMargin: 0 })
        }
      }
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .width('100%')
  }
}

@Component
struct SidebarContent {
  activeRoute: string = ROUTE_TERMINAL_HOME
  onNavigate: (() => void) | null = null
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('userInfo') userInfoStr: string = ''
  @State recentSessions: SessionInfo[] = []
  @State sessionError: string = ''
  private apiClient: RestApiClient = new RestApiClient()

  aboutToAppear() {
    this.loadRecentSessions()
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.app_icon'))
          .width(36)
          .height(36)
          .borderRadius(10)

        Column() {
          Text('云枢终端')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))
            .maxLines(1)

          Text('CortexTerminal')
            .fontSize(11)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .height(64)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      this.NavItem('⌘', '终端会话', ROUTE_TERMINAL_HOME,
        this.activeRoute === ROUTE_TERMINAL_HOME || this.activeRoute === ROUTE_TERMINAL_SESSION)

      Column() {
        Text('最近 5 个会话')
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ top: 14, bottom: 8 })

        if (this.recentSessions.length === 0) {
          Text(this.sessionError.length > 0 ? '会话加载失败' : '暂无最近会话')
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        } else {
          ForEach(this.recentSessions.slice(0, 5), (session: SessionInfo) => {
            this.RecentSessionItem(session)
          }, (session: SessionInfo) => session.id)
        }

        Text('更多会话')
          .fontSize(13)
          .fontColor($r('app.color.terminal_secondary'))
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .onClick(() => {
            this.navigate(ROUTE_TERMINAL_HOME)
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Divider()
        .color($r('app.color.terminal_outline_variant'))
        .margin({ left: 16, right: 16, top: 10, bottom: 10 })

      this.NavItem('▦', 'Workers', ROUTE_WORKERS,
        this.activeRoute === ROUTE_WORKERS || this.activeRoute === ROUTE_WORKER_DETAIL)
      this.NavItem('⚙', 'Settings', ROUTE_SETTINGS, this.activeRoute === ROUTE_SETTINGS)

      Blank()

      Row() {
        Text(this.userInitial())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .borderRadius(19)

        Column() {
          Text(this.userDisplayName())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('账号设置')
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
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
      .backgroundColor($r('app.color.terminal_surface_container'))
      .onClick(() => {
        this.navigate(ROUTE_SETTINGS)
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .borderColor($r('app.color.terminal_outline_variant'))
    .borderWidth({ right: 1 })
  }

  @Builder
  NavItem(icon: string, label: string, route: string, selected: boolean) {
    Row() {
      Text(icon)
        .fontSize(16)
        .fontColor(selected ? $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_on_surface_variant'))
        .width(28)
        .textAlign(TextAlign.Center)

      Text(label)
        .fontSize(14)
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(selected ? $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_primary'))
        .margin({ left: 8 })
    }
    .width('calc(100% - 24vp)')
    .height(44)
    .padding({ left: 10, right: 10 })
    .margin({ left: 12, right: 12, top: 4 })
    .borderRadius(10)
    .backgroundColor(selected ? $r('app.color.terminal_secondary_container') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.navigate(route)
    })
  }

  @Builder
  RecentSessionItem(session: SessionInfo) {
    Row() {
      Circle()
        .width(7)
        .height(7)
        .fill(this.sessionStatusColor(session.status))

      Column() {
        Text(session.name || `session ${session.id.substring(0, 8)}`)
          .fontSize(13)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(session.status.length > 0 ? session.status : 'idle')
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 8, right: 8 })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      AppStorage.setOrCreate('navSessionId', session.id)
      AppStorage.setOrCreate('navSessionName', session.name || 'Terminal')
      this.navigate(ROUTE_TERMINAL_SESSION)
    })
  }

  private navigate(route: string) {
    if (this.onNavigate) {
      this.onNavigate()
    }
    this.pageStack.replacePath({ name: route })
  }

  private async loadRecentSessions() {
    this.sessionError = ''
    try {
      this.recentSessions = (await this.apiClient.listSessions()).slice(0, 5)
    } catch (e) {
      this.sessionError = (e as Error).message || 'failed'
      this.recentSessions = []
    }
  }

  private sessionStatusColor(status: string): ResourceColor {
    switch (status.toLowerCase()) {
      case 'live':
      case 'connected':
      case 'running':
        return $r('app.color.terminal_tertiary')
      case 'expired':
      case 'failed':
      case 'error':
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_outline')
    }
  }

  private userDisplayName(): string {
    if (this.userInfoStr.length === 0) {
      return '已登录用户'
    }
    try {
      const user = JSON.parse(this.userInfoStr) as Record<string, string>
      return user['displayName'] || user['username'] || '已登录用户'
    } catch (e) {
      return '已登录用户'
    }
  }

  private userInitial(): string {
    const name = this.userDisplayName()
    if (name.length === 0) {
      return 'U'
    }
    return name.substring(0, 1).toUpperCase()
  }
}
