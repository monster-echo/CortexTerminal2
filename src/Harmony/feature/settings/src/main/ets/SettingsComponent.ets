/**
 * @file SettingsComponent.ets
 * @brief Settings feature entry component with NavDestination
 *
 * Entry point for the settings feature when navigated to from the shell.
 */
import { SettingsPage } from './view/SettingsPage'

/**
 * Main SettingsComponent that acts as a NavDestination wrapper.
 */
@Component
export struct SettingsComponent {
  build() {
    NavDestination() {
      SettingsPage()
    }
    .title('Settings')
    .hideTitleBar(true)
  }
}
