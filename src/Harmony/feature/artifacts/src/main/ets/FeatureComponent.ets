/**
 * @file FeatureComponent.ets
 * @brief Artifacts feature route entry.
 */
import { registerRoute } from 'routermodule'
import { ArtifactsPage } from './view/ArtifactsPage'

registerRoute({ name: 'artifacts/Page' })

@Component
export struct ArtifactsPageRoute {
  build() {
    NavDestination() {
      ArtifactsPage()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }
}
