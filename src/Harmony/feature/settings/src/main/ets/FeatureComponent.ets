/**
 * @file FeatureComponent.ets
 * @brief Settings feature route entry.
 */
import { registerRoute } from 'routermodule'
import { SettingsPage } from './view/SettingsPage'

registerRoute({ name: 'settings/Page' })

@Component
export struct SettingsPageRoute {
  build() {
    NavDestination() {
      SettingsPage()
    }
    .hideTitleBar(true)
  }
}
