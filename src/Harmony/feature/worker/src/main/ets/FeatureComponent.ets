/**
 * @file FeatureComponent.ets
 * @brief Worker feature route entry with @AppRouter registration.
 */
import { AppRouter } from 'routermodule'
import { WorkerListPage } from './view/WorkerListPage'

@AppRouter({ name: 'worker/List' })
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
