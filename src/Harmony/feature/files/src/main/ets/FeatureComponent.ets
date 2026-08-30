/**
 * @file FeatureComponent.ets
 * @brief Files feature route entry.
 */
import { registerRoute } from 'routermodule'
import { FileBrowserPage } from './view/FileBrowserPage'

registerRoute({ name: 'files/Page' })

@Component
export struct FilesPageRoute {
  build() {
    NavDestination() {
      FileBrowserPage()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
  }
}
