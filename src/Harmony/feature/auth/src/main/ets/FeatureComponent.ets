/**
 * @file FeatureComponent.ets
 * @brief Auth feature route entry.
 */
import { registerRoute } from 'routermodule'
import { LoginPage } from './view/LoginPage'

registerRoute({ name: 'auth/Login' })

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
