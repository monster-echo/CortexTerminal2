/**
 * @file SidebarContent.ets
 * @brief Navigation sidebar extracted from Index.ets.
 */
import { ApiService, I18n, AuthState, SessionInfo, RouteName, TerminalNavParam, lightHaptic } from '@rwecho/core'

@Component
export struct SidebarContent {
  activeRoute: string = RouteName.SESSION_HOME
  onNavigate?: (() => void) | null = null
  @Consume('pageStack') pageStack: NavPathStack
  @State recentSessions: SessionInfo[] = []
  @State sessionError: string = ''

  aboutToAppear() {
    this.loadRecentSessions()
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
            .fontColor($r('app.color.terminal_primary'))
            .maxLines(1)

          Text('云枢终端')
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

      // Nav: Terminal Sessions
      this.NavItem('⌘', I18n.get('sidebar.sessions'), RouteName.SESSION_HOME,
        this.activeRoute === RouteName.SESSION_HOME || this.activeRoute === RouteName.TERMINAL_SESSION)

      // Recent sessions
      Column() {
        Text(I18n.get('session.home.tab_active'))
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ top: 14, bottom: 8 })

        if (this.recentSessions.length === 0) {
          Text(this.sessionError.length > 0 ? I18n.get('common.error') : I18n.get('session.home.tab_history'))
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        } else {
          ForEach(this.recentSessions.slice(0, 5), (session: SessionInfo) => {
            this.RecentSessionItem(session)
          }, (session: SessionInfo) => session.id)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Divider()
        .color($r('app.color.terminal_outline_variant'))
        .margin({ left: 16, right: 16, top: 10, bottom: 10 })

      // Nav: Workers
      this.NavItem('▦', I18n.get('sidebar.workers'), RouteName.WORKER_LIST,
        this.activeRoute === RouteName.WORKER_LIST || this.activeRoute === RouteName.WORKER_DETAIL)

      // Nav: Settings
      this.NavItem('⚙', I18n.get('sidebar.settings'), RouteName.SETTINGS,
        this.activeRoute === RouteName.SETTINGS)

      Blank()

      // User profile
      Row() {
        Text(AuthState.getDisplayName().substring(0, 1).toUpperCase() || 'U')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .borderRadius(19)

        Column() {
          Text(AuthState.getDisplayName() || I18n.get('auth.login.title'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(I18n.get('settings.account'))
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
        lightHaptic()
        this.navigate(RouteName.SETTINGS)
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
      lightHaptic()
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
      lightHaptic()
      const param = new TerminalNavParam()
      param.sessionId = session.id
      param.sessionName = session.name || 'Terminal'
      this.navigate(RouteName.TERMINAL_SESSION, param)
    })
  }

  private navigate(route: string, param?: Object) {
    if (this.onNavigate) {
      this.onNavigate()
    }
    this.pageStack.replacePath({ name: route, param: param })
  }

  private async loadRecentSessions() {
    this.sessionError = ''
    try {
      const sessions = await ApiService.listSessions()
      this.recentSessions = sessions.filter(s => {
        const status = s.status.toLowerCase()
        return status === 'running' || status === 'idle' || status === 'live' || status === 'connected'
      }).slice(0, 5)
    } catch (e) {
      this.sessionError = (e as Error).message
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
}
