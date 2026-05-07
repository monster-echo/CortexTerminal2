/**
 * @file TerminalComponent.ets
 * @brief Terminal feature entry component with NavDestination
 *
 * Provides the main terminal navigation destination that hosts
 * TerminalHome. The shell Navigation handles routing.
 */
import { TerminalHome } from './view/TerminalHome'

/**
 * Main TerminalComponent that acts as a NavDestination wrapper.
 * Entry point for the terminal feature when navigated to from the shell.
 */
@Component
export struct TerminalComponent {
  build() {
    NavDestination() {
      TerminalHome()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }
}
