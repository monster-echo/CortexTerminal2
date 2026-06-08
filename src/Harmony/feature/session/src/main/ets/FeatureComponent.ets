import { SessionHomePage } from './view/SessionHomePage'

@Component
export struct SessionHomeRoute {
  build() {
    NavDestination() {
      SessionHomePage()
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.terminal_surface'))
    .onBackPressed(() => true)
  }
}
