/**
 * @file Index.ets
 * @brief Root Navigation shell — minimal router + auth state watcher.
 */
import { DynamicsRouter, Interceptor } from 'routermodule'
import { AuthInterceptorExecute } from '../interceptor/AuthInterceptor'
import { AuthService, RouteName } from '@rwecho/core'
import { LoginPage, ActivateWorkerPage } from '@rwecho/auth'
import { TerminalPage } from '@rwecho/terminal'
import { ArtifactsPage } from '@rwecho/artifacts'
import { ShellScaffold } from '../shell/ShellScaffold'
import { AccountSecurityPage, ChangePasswordPage, WebPage, ContactSupportPage, FeedbackPage, ImagePreviewPage } from '@rwecho/settings'

@Entry
@Component
struct Index {
  @Provide('pageStack') pageStack: NavPathStack = DynamicsRouter.navPathStack
  @StorageLink('authToken') @Watch('onAuthChanged') authToken: string = ''
  @StorageLink('isLoggedIn') @Watch('onAuthChanged') isLoggedIn: boolean = false
  private isInitialized: boolean = false

  aboutToAppear() {
    Interceptor.registerInterceptorPage(new AuthInterceptorExecute())

    console.info(`[Index] Startup: isLoggedIn=${this.isLoggedIn} token=${this.authToken.length > 0 ? 'yes' : 'no'}`)
    if (this.isLoggedIn && this.authToken.length > 0) {
      console.info('[Index] Routing to HOME + ensureAuthenticated')
      this.pageStack.replacePath({ name: RouteName.SESSION_HOME })
      AuthService.ensureAuthenticated()
    } else {
      console.info('[Index] Routing to LOGIN')
      this.pageStack.replacePath({ name: RouteName.AUTH_LOGIN })
    }
    this.isInitialized = true
  }

  onAuthChanged() {
    console.info(`[Index] onAuthChanged: isLoggedIn=${this.isLoggedIn} token=${this.authToken.length > 0 ? 'yes' : 'no'} initialized=${this.isInitialized}`)
    if (!this.isInitialized) {
      return
    }
    if (!this.isLoggedIn && this.authToken.length === 0) {
      console.info('[Index] onAuthChanged: clearing stack -> LOGIN')
      this.pageStack.clear()
      this.pageStack.replacePath({ name: RouteName.AUTH_LOGIN })
    }
  }

  build() {
    Navigation(this.pageStack) {
      Column()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === RouteName.AUTH_LOGIN) {
      NavDestination() {
        LoginPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === RouteName.SESSION_HOME) {
      NavDestination() {
        ShellScaffold({ activeRoute: RouteName.SESSION_HOME })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === RouteName.TERMINAL_SESSION) {
      NavDestination() {
        TerminalPage()
      }
      .hideTitleBar(true)
      .backgroundColor('#0f1419')
    } else if (name === RouteName.WORKER_LIST) {
      NavDestination() {
        ShellScaffold({ activeRoute: RouteName.WORKER_LIST })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === RouteName.WORKER_DETAIL) {
      NavDestination() {
        ShellScaffold({ activeRoute: RouteName.WORKER_DETAIL })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.ACCOUNT_SECURITY) {
      NavDestination() {
        AccountSecurityPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.CHANGE_PASSWORD) {
      NavDestination() {
        ChangePasswordPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.SETTINGS) {
      NavDestination() {
        ShellScaffold({ activeRoute: RouteName.SETTINGS })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
      .onBackPressed(() => true)
    } else if (name === RouteName.ACTIVATE_WORKER) {
      NavDestination() {
        ActivateWorkerPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.WEB_PAGE) {
      NavDestination() {
        WebPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.ARTIFACTS_PAGE) {
      NavDestination() {
        ArtifactsPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.CONTACT_SUPPORT) {
      NavDestination() {
        ContactSupportPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.FEEDBACK) {
      NavDestination() {
        FeedbackPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.terminal_surface'))
    } else if (name === RouteName.IMAGE_PREVIEW) {
      NavDestination() {
        ImagePreviewPage()
      }
      .hideTitleBar(true)
      .backgroundColor(Color.Black)
    }
  }
}
