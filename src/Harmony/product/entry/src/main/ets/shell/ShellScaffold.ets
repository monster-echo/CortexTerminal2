/**
 * @file ShellScaffold.ets
 * @brief Main app shell with sidebar container extracted from Index.ets.
 */
import { RouteName, I18n } from '@rwecho/core'
import { SessionHomePage } from '@rwecho/session'
import { TerminalPage } from '@rwecho/terminal'
import { WorkerListPage, WorkerDetailPage } from '@rwecho/worker'
import { SettingsPage } from '@rwecho/settings'
import { SidebarContent } from './SidebarContent'
import { AppBar } from './AppBar'

@Component
export struct ShellScaffold {
  activeRoute: string = RouteName.SESSION_HOME
  @Consume('pageStack') pageStack: NavPathStack
  @State sidebarOpen: boolean = false
  @StorageLink('sidebarOpen') @Watch('onSidebarChanged') sidebarTrigger: boolean = false

  onSidebarChanged() {
    if (this.sidebarTrigger) {
      this.sidebarOpen = true
      // Reset trigger after a tick
      setTimeout(() => { this.sidebarTrigger = false }, 100)
    }
  }

  onBackPress(): boolean {
    if (this.sidebarOpen) {
      this.sidebarOpen = false
      return true
    }
    return false
  }

  build() {
    SideBarContainer(SideBarContainerType.Overlay) {
      SidebarContent({
        activeRoute: this.activeRoute,
        onNavigate: () => { this.sidebarOpen = false }
      })

      Column() {
        if (this.activeRoute !== RouteName.TERMINAL_SESSION && this.activeRoute !== RouteName.WORKER_DETAIL && this.activeRoute !== RouteName.SESSION_HOME) {
          AppBar({
            title: this.pageTitle(),
            showHamburger: this.activeRoute === RouteName.SESSION_HOME,
            showCreateButton: this.activeRoute === RouteName.SESSION_HOME,
            onToggleSidebar: () => { this.sidebarOpen = !this.sidebarOpen },
            onNavigateBack: () => { this.pageStack.replacePath({ name: RouteName.SESSION_HOME }) }
          })
        }

        this.ActivePage()
      }
      .width('100%')
      .height('100%')
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
  ActivePage() {
    if (this.activeRoute === RouteName.SESSION_HOME) {
      SessionHomePage()
    } else if (this.activeRoute === RouteName.TERMINAL_SESSION) {
      TerminalPage()
    } else if (this.activeRoute === RouteName.WORKER_LIST) {
      WorkerListPage()
    } else if (this.activeRoute === RouteName.WORKER_DETAIL) {
      WorkerDetailPage()
    } else if (this.activeRoute === RouteName.SETTINGS) {
      SettingsPage()
    } else {
      SessionHomePage()
    }
  }

  private pageTitle(): string {
    switch (this.activeRoute) {
      case RouteName.SESSION_HOME:
        return I18n.get('session.home.title')
      case RouteName.WORKER_LIST:
        return I18n.get('worker.list.title')
      case RouteName.SETTINGS:
        return I18n.get('settings.title')
      default:
        return ''
    }
  }
}
