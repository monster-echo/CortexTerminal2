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
import { TerminalChrome } from '../model/TerminalThemeProfile'
import { PageMenuItem } from './PageLayout'

@Component
export struct OverflowMenuButton {
  items: PageMenuItem[] = []
  @Prop chromeJson: string = ''

  private tone(role: string): ResourceColor {
    if (this.chromeJson.length > 0) {
      const chrome = TerminalChrome.fromJson(this.chromeJson)
      if (role === 'background') return chrome.surfaceHigh
      if (role === 'border') return chrome.outlineVariant
      return chrome.onSurface
    }
    if (role === 'background') return $r('app.color.terminal_background_menu')
    if (role === 'border') return $r('app.color.terminal_border_subtle')
    return $r('app.color.terminal_text')
  }

  @Builder
  MenuContent() {
    Column() {
      ForEach(this.items, (item: PageMenuItem, idx: number) => {
        Text(item.value)
          .fontSize(15)
          .fontColor(this.tone('foreground'))
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
            .color(this.tone('border'))
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
        Circle().width(4).height(4).fill(this.tone('foreground'))
        Circle().width(4).height(4).fill(this.tone('foreground'))
        Circle().width(4).height(4).fill(this.tone('foreground'))
      }
    }
    .width(40)
    .height(40)
    .padding(0)
    .borderRadius(20)
    .backgroundColor(Color.Transparent)
    .bindMenu(this.MenuContent, {
      backgroundColor: this.tone('background'),
      borderRadius: 12,
      outlineColor: Color.Transparent
    })
  }
}