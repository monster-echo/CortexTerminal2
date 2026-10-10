/**
 * @file FeatureComponent.ets
 * @brief Files feature route entry.
 *
 * 系统返回手势（左滑/物理返回）在非根目录时先回上一级目录（goUpTick 信号驱动
 * FileBrowserPage 逐级向上），到根目录才放行 pop 退出页面。
 */
import { registerRoute } from 'routermodule'
import { FileBrowserPage } from './view/FileBrowserPage'

registerRoute({ name: 'files/Page' })

@Component
export struct FilesPageRoute {
  @State pathSegments: string[] = []
  @State goUpTick: number = 0

  build() {
    NavDestination() {
      FileBrowserPage({ pathSegments: this.pathSegments, goUpTick: this.goUpTick })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_background'))
    .onBackPressed(() => {
      if (this.pathSegments.length > 0) {
        this.goUpTick = this.goUpTick + 1
        return true
      }
      return false
    })
  }
}
