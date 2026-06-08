/**
 * @file FeatureComponent.ets
 * @brief Auth feature route entry with @AppRouter registration.
 */
import { AppRouter } from 'routermodule'
import { LoginPage } from './view/LoginPage'

@AppRouter({ name: 'auth/Login' })
@Component
export struct AuthLogin {
  build() {
    NavDestination() {
      LoginPage()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
    .onBackPressed(() => true)
  }
}
