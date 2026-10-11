import { PreferencesPage } from './PreferencesPage'

@Component
export struct SettingsPage {
  build() {
    PreferencesPage({ embedded: true })
  }
}
