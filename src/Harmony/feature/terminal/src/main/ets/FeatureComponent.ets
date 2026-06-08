/**
 * @file FeatureComponent.ets
 * @brief Terminal feature route entry.
 */
import { registerRoute } from 'routermodule'
import { TerminalPage } from './view/TerminalPage'

registerRoute({ name: 'terminal/Session' })

@Component
export struct TerminalSessionRoute {
  build() {
    NavDestination() {
      TerminalPage()
    }
    .hideTitleBar(true)
    .backgroundColor('#0f1419')
  }
}
