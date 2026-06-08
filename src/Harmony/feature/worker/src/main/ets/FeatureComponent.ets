/**
 * @file FeatureComponent.ets
 * @brief Worker feature route entry.
 */
import { registerRoute } from 'routermodule'
import { WorkerListPage } from './view/WorkerListPage'

registerRoute({ name: 'worker/List' })

@Component
export struct WorkerListRoute {
  build() {
    NavDestination() {
      WorkerListPage()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }
}
