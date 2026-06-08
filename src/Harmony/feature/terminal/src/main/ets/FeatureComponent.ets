/**
 * @file FeatureComponent.ets
 * @brief Terminal feature route entry with @AppRouter registration.
 */
import { AppRouter } from 'routermodule'
import { TerminalPage } from './view/TerminalPage'

@AppRouter({ name: 'terminal/Session' })
@Component
export struct TerminalSessionRoute {
  build() {
    NavDestination() {
      TerminalPage()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }
}
