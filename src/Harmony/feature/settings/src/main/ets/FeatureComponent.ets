/**
 * @file FeatureComponent.ets
 * @brief Settings feature route entry with @AppRouter registration.
 */
import { AppRouter } from 'routermodule'
import { SettingsPage } from './view/SettingsPage'

@AppRouter({ name: 'settings/Page' })
@Component
export struct SettingsPageRoute {
  build() {
    NavDestination() {
      SettingsPage()
    }
    .hideTitleBar(true)
  }
}
