/**
 * @file AuthComponent.ets
 * @brief Auth feature entry component with NavDestination
 *
 * Provides the main auth navigation destination that hosts
 * LoginPage and ActivateWorkerPage based on auth state.
 */
import { LoginPage } from './view/LoginPage'
import { ActivateWorkerPage } from './view/ActivateWorkerPage'

/**
 * Main AuthComponent that acts as a NavDestination wrapper.
 * Entry point for the auth feature when navigated to from the shell.
 */
@Component
export struct AuthComponent {
  @StorageLink('authToken') authToken: string = ''
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false

  build() {
    NavDestination() {
      Column() {
        if (!this.isLoggedIn || this.authToken.length === 0) {
          LoginPage()
        } else {
          ActivateWorkerPage()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
    .onBackPressed(() => true)
  }
}
