/**
 * @file FeatureComponent.ets
 * @brief Terminal feature route entry.
 */
import { registerRoute } from 'routermodule'
import { TerminalComponent } from './TerminalComponent'

registerRoute({ name: 'terminal/Session' })

@Component
export struct TerminalSessionRoute {
  build() {
    TerminalComponent()
  }
}
