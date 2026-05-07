/**
 * @file WorkerComponent.ets
 * @brief Worker feature entry component with NavDestination
 *
 * Provides the main worker navigation destination that hosts
 * WorkerListPage. Worker detail navigation goes through the
 * shell Navigation.
 */
import { WorkerListPage } from './view/WorkerListPage'

/**
 * Main WorkerComponent that acts as a NavDestination wrapper.
 * Entry point for the worker feature when navigated to from the shell.
 */
@Component
export struct WorkerComponent {
  build() {
    NavDestination() {
      WorkerListPage()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }
}
