/**
 * @file ShellScaffold.ets
 * @brief Main app shell with sidebar container.
 *
 * Renders a unified AppBar for all pages except TerminalPage.
 * Top-level routes (SessionHome, Workers, Settings) get hamburger button.
 * Sub-pages (WorkerDetail, AccountSecurity, ActivateWorker) get back arrow.
 */
import { RouteName, I18n, AppBar } from '@rwecho/core'
import { SessionHomePage } from '@rwecho/session'
import { TerminalPage } from '@rwecho/terminal'
import { WorkerListPage, WorkerDetailPage } from '@rwecho/worker'
import { SettingsPage, MePage } from '@rwecho/settings'
import { SidebarContent } from './SidebarContent'

@Component
export struct ShellScaffold {
  activeRoute: string = RouteName.SESSION_HOME
  @StorageLink('language') currentLang: string = 'en'
  @Consume('pageStack') pageStack: NavPathStack
  @State sidebarOpen: boolean = false
  @StorageLink('sidebarOpen') @Watch('onSidebarChanged') sidebarTrigger: boolean = false
  @StorageLink('navWorkerName') navWorkerName: string = 'Worker'
  // 顶层页通过压栈带 param 进入时为 true：AppBar 显示返回键而不是汉堡按钮。
  subPage: boolean = false

  onSidebarChanged() {
    if (this.sidebarTrigger) {
      this.getUIContext()?.animateTo({ duration: 300 }, () => {
        this.sidebarOpen = true
      })
      setTimeout(() => { this.sidebarTrigger = false }, 100)
    }
  }

  onBackPress(): boolean {
    if (this.sidebarOpen) {
      this.getUIContext()?.animateTo({ duration: 300 }, () => {
        this.sidebarOpen = false
      })
      return true
    }
    return false
  }

  private isTopRoute(): boolean {
    return this.activeRoute === RouteName.SESSION_HOME
      || this.activeRoute === RouteName.WORKER_LIST
      || this.activeRoute === RouteName.SETTINGS
  }

  private showBack(): boolean {
    return this.subPage
      && (this.activeRoute === RouteName.WORKER_LIST
        || this.activeRoute === RouteName.SETTINGS_ROOT)
  }

  build() {
    SideBarContainer(SideBarContainerType.Overlay) {
      SidebarContent({
        activeRoute: this.activeRoute,
        onNavigate: () => {
          this.getUIContext()?.animateTo({ duration: 300 }, () => {
            this.sidebarOpen = false
          })
        }
      })

      Column() {
        if (this.activeRoute !== RouteName.TERMINAL_SESSION) {
          AppBar({
            title: this.pageTitle(),
            showHamburger: this.isTopRoute() && !this.showBack(),
            showCreateButton: this.activeRoute === RouteName.SESSION_HOME,
            onToggleSidebar: () => {
              this.getUIContext()?.animateTo({ duration: 300 }, () => {
                this.sidebarOpen = !this.sidebarOpen
              })
            },
            onNavigateBack: () => { this.pageStack.pop() },
            onCreateSession: () => {
              AppStorage.setOrCreate('triggerCreateSession', true)
            }
          })
        }

        this.ActivePage()
      }
      .width('100%')
      .height('100%')
      .overlay(this.SidebarOverlay())
    }
    .showSideBar($$this.sidebarOpen)
    .showControlButton(false)
    .sideBarWidth(304)
    .clip(false)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  SidebarOverlay() {
    Row() {}
      .onClick(() => {
        this.getUIContext()?.animateTo({ duration: 300 }, () => {
          this.sidebarOpen = false
        })
      })
      .visibility(this.sidebarOpen ? Visibility.Visible : Visibility.Hidden)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .opacity(0.3)
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
      MePage()
    } else if (this.activeRoute === RouteName.SETTINGS_ROOT) {
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
        return I18n.get('me.title')
      case RouteName.SETTINGS_ROOT:
        return I18n.get('settings.title')
      case RouteName.WORKER_DETAIL:
        return this.navWorkerName
      case RouteName.ACCOUNT_SECURITY:
        return I18n.get('security.title')
      case RouteName.ACTIVATE_WORKER:
        return I18n.get('worker.activate.title')
      default:
        return ''
    }
  }
}
