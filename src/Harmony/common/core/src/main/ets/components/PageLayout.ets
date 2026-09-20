/**
 * @file PageLayout.ets
 * @brief Standard layout for sub-pages pushed onto NavPathStack.
 *
 * Provides: AppBar (back + title) + content slot.
 * Used by AccountSecurityPage, ActivateWorkerPage, etc.
 * TerminalPage manages its own AppBar due to custom toolbar needs.
 */

import { clickHaptic } from '../utils/HapticUtils'

/** One entry of the AppBar "···" overflow menu. */
export class PageMenuItem {
  public value: string = ''
  public action: () => void = () => {}
}

@Component
export struct PageLayout {
  title: string = ''
  onBack?: (() => void) | null = null
  /** Optional AppBar "···" overflow menu entries. Rendered only when non-empty. */
  moreMenuItems: PageMenuItem[] | null = null
  @BuilderParam content: () => void
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('language') currentLang: string = 'en'

  build() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          clickHaptic()
          if (this.onBack) {
            this.onBack()
          } else {
            this.pageStack.pop()
          }
        })

        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })

        if (this.moreMenuItems !== null && this.moreMenuItems.length > 0) {
          Text('···')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              clickHaptic()
            })
            .bindMenu(this.moreMenuItems)
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        this.content()
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }
}
