/**
 * @file TerminalComponent.ets
 * @brief Terminal feature entry component with NavDestination
 *
 * Provides the main terminal navigation destination that hosts
 * TerminalHome. The shell Navigation handles routing.
 */
import { TerminalChrome } from '@rwecho/core'
import { TerminalPage } from './view/TerminalPage'

/**
 * Main TerminalComponent that acts as a NavDestination wrapper.
 * Entry point for the terminal feature when navigated to from the shell.
 */
@Component
export struct TerminalComponent {
  @StorageLink('terminalChromeJson') chromeJson: string = ''

  private chrome(): TerminalChrome {
    return TerminalChrome.fromJson(this.chromeJson)
  }

  build() {
    NavDestination() {
      TerminalPage()
    }
    .hideTitleBar(true)
    .backgroundColor(this.chrome().background)
  }
}
