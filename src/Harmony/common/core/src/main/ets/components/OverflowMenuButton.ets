/**
 * @file OverflowMenuButton.ets
 * @brief AppBar overflow menu button — the standard three-dot affordance backed by
 * ArkUI's system menu (bindMenu).
 *
 * Shared by PageLayout (sub-pages) and TerminalPage (its own AppBar) so secondary
 * actions such as port forwarding and file browsing live in one predictable place.
 */
import { PageMenuItem } from './PageLayout'

@Component
export struct OverflowMenuButton {
  items: PageMenuItem[] = []

  build() {
    Button() {
      Row({ space: 3 }) {
        Circle().width(4).height(4).fill($r('app.color.terminal_primary'))
        Circle().width(4).height(4).fill($r('app.color.terminal_primary'))
        Circle().width(4).height(4).fill($r('app.color.terminal_primary'))
      }
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor(Color.Transparent)
    .bindMenu(this.items)
  }
}