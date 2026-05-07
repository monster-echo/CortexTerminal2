/**
 * @file Index.ets
 * @brief Main Navigation shell
 *
 * Provides the top-level Navigation with NavPathStack that
 * dispatches to all feature pages.
 */
import { TerminalComponent } from '@rwecho/terminal'
import { TerminalPage } from '@rwecho/terminal'
import { AuthComponent } from '@rwecho/auth'
import { WorkerComponent } from '@rwecho/worker'
import { WorkerDetailPage } from '@rwecho/worker'
import { SettingsComponent } from '@rwecho/settings'

@Entry
@Component
struct Index {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack()
  @StorageLink('authToken') authToken: string = ''
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false

  aboutToAppear() {
    if (this.authToken && this.authToken.length > 0) {
      this.pageStack.replacePath({ name: 'TerminalHome' })
    } else {
      this.pageStack.replacePath({ name: 'Auth' })
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
    if (name === 'TerminalHome') {
      TerminalComponent()
    } else if (name === 'TerminalSession') {
      TerminalPage()
    } else if (name === 'Auth') {
      AuthComponent()
    } else if (name === 'Workers') {
      WorkerComponent()
    } else if (name === 'WorkerDetail') {
      WorkerDetailPage()
    } else if (name === 'Settings') {
      SettingsComponent()
    }
  }
}
