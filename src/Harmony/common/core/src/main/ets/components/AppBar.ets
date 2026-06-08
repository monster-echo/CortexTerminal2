/**
 * @file AppBar.ets
 * @brief Shared top app bar component.
 *
 * Top-level pages: hamburger (sidebar toggle) + title + optional action.
 * Sub-pages: back arrow (pop) + title.
 */

import { clickHaptic } from '../utils/HapticUtils'

@Component
export struct AppBar {
  title: string = ''
  showHamburger: boolean = true
  onToggleSidebar?: (() => void) | null = null
  onNavigateBack?: (() => void) | null = null
  onCreateSession?: (() => void) | null = null
  showCreateButton: boolean = false

  build() {
    Row() {
      if (this.showHamburger) {
        Button() {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          clickHaptic()
          if (this.onToggleSidebar) this.onToggleSidebar()
        })
      } else {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          clickHaptic()
          if (this.onNavigateBack) this.onNavigateBack()
        })
      }

      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .layoutWeight(1)
        .margin({ left: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.showCreateButton) {
        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          clickHaptic()
          if (this.onCreateSession) this.onCreateSession()
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }
}
