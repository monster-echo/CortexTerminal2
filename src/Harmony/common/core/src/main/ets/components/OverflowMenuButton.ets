/**
 * @file OverflowMenuButton.ets
 * @brief AppBar overflow menu button — the standard three-dot affordance opening a
 * bindMenu popup whose content is drawn with the app's design tokens.
 *
 * Shared by PageLayout (sub-pages) and TerminalPage (its own AppBar) so secondary
 * actions such as port forwarding and file browsing live in one predictable place.
 * The default system menu renders light-on-white regardless of the app theme, so
 * the popup content is a custom builder: same system popup mechanics, matching style.
 */
import { PageMenuItem } from './PageLayout'

@Component
export struct OverflowMenuButton {
  items: PageMenuItem[] = []
  // 弹窗容器的背景/圆角走 MenuOptions——容器默认 outline 在深色下会露出一圈浅色边框
  private menuOptions: MenuOptions = {
    backgroundColor: $r('app.color.terminal_surface_container_highest'),
    borderRadius: 12,
    outlineColor: Color.Transparent,
  }

  @Builder
  MenuContent() {
    Column() {
      ForEach(this.items, (item: PageMenuItem, idx: number) => {
        Text(item.value)
          .fontSize(15)
          .fontColor($r('app.color.terminal_primary'))
          .constraintSize({ maxWidth: 220 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .width('100%')
          .textAlign(TextAlign.Start)
          .onClick(() => {
            item.action()
          })
        if (idx < this.items.length - 1) {
          Divider()
            .color($r('app.color.terminal_outline_variant'))
            .margin({ left: 12, right: 12 })
        }
      }, (item: PageMenuItem) => item.value)
    }
    .width(180)
    .padding(6)
    .alignItems(HorizontalAlign.Start)
  }

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
    .padding(0)
    .borderRadius(20)
    .backgroundColor(Color.Transparent)
    .bindMenu(this.MenuContent, this.menuOptions)
  }
}