/**
 * @file ShellScaffold.ets
 * @brief Main app shell with sidebar container.
 *
 * Renders a unified AppBar for all pages except TerminalPage.
 * The workspace list is the root. All pushed pages use a back arrow.
 */
import { RouteName, I18n, AppBar } from '@rwecho/core'
import { SessionHomePage, WorkspaceHomePage } from '@rwecho/session'
import { TerminalPage } from '@rwecho/terminal'
import { WorkerListPage, WorkerDetailPage } from '@rwecho/worker'
import { SettingsPage, MePage } from '@rwecho/settings'
import { SidebarContent } from './SidebarContent'

@Component
export struct ShellScaffold {
  activeRoute: string = RouteName.SESSION_HOME
  @StorageLink('language') currentLang: string = 'en'
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('shellSidebarVisible') sidebarOpen: boolean = false
  @StorageLink('sidebarOpen') @Watch('onSidebarChanged') sidebarTrigger: boolean = false
  @StorageLink('navWorkerName') navWorkerName: string = 'Computer'
  @StorageLink('navWorkspaceName') navWorkspaceName: string = ''
  // 压栈进入的子页面显示返回键。
  subPage: boolean = false

  onSidebarChanged() {
    if (this.sidebarTrigger) {
      this.getUIContext()?.animateTo({ duration: 300 }, () => {
        this.sidebarOpen = true
      })
      setTimeout(() => { this.sidebarTrigger = false }, 100)
    }
  }

  private isTopRoute(): boolean {
    return this.activeRoute === RouteName.SESSION_HOME
  }

  private showBack(): boolean {
    return this.subPage
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
            title: this.pageTitle() + (this.currentLang ? '' : ''),
            showHamburger: this.isTopRoute() && !this.showBack(),
            showCreateButton: this.activeRoute === RouteName.SESSION_HOME || this.activeRoute === RouteName.WORKSPACE_HOME,
            showSettingsButton: this.activeRoute === RouteName.SETTINGS,
            onOpenSettings: () => { this.pageStack.pushPath({ name: RouteName.SETTINGS_ROOT }) },
            onToggleSidebar: () => {
              this.getUIContext()?.animateTo({ duration: 300 }, () => {
                this.sidebarOpen = !this.sidebarOpen
                if (this.sidebarOpen) AppStorage.setOrCreate('sidebarRefreshTick', Date.now())
              })
            },
            onNavigateBack: () => { this.pageStack.pop() },
            onCreateSession: () => {
              AppStorage.setOrCreate(this.activeRoute === RouteName.WORKSPACE_HOME ? 'triggerWorkspaceSession' : 'triggerCreateSession', true)
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
    .sideBarWidth(312)
    .clip(false)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_background'))
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
      .backgroundColor($r('app.color.terminal_scrim'))
      .opacity(0.3)
  }

  @Builder
  ActivePage() {
    if (this.activeRoute === RouteName.SESSION_HOME) {
      SessionHomePage()
    } else if (this.activeRoute === RouteName.UNGROUPED) {
      SessionHomePage({ ungroupedOnly: true })
    } else if (this.activeRoute === RouteName.WORKSPACE_HOME) {
      WorkspaceHomePage()
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
        return I18n.get('workspaces.title')
      case RouteName.UNGROUPED:
        return I18n.get('workspace.home.ungrouped')
      case RouteName.WORKER_LIST:
        return I18n.get('worker.list.title')
      case RouteName.SETTINGS:
        return I18n.get('me.title')
      case RouteName.SETTINGS_ROOT:
        return I18n.get('settings.title')
      case RouteName.WORKER_DETAIL:
        return this.navWorkerName
      case RouteName.WORKSPACE_HOME:
        return this.navWorkspaceName
      case RouteName.ACCOUNT_SECURITY:
        return I18n.get('security.title')
      case RouteName.ACTIVATE_WORKER:
        return I18n.get('worker.activate.title')
      default:
        return ''
    }
  }
}
