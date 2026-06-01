/**
 * @file VirtualKeyBar.ets
 * @brief Single-row horizontally scrollable virtual keyboard bar
 *
 * Provides modifier keys and special keys in a single scrollable row.
 * All touch targets meet the 44px minimum accessibility requirement.
 */
import { pasteboard } from '@kit.BasicServicesKit'

type OnKeyPressCallback = (key: string) => void

@Component
export struct VirtualKeyBar {
  onKeyPress: OnKeyPressCallback = (_key: string) => {}
  onCopy: (() => void) | null = null
  onDismiss: (() => void) | null = null
  @State ctrlLatched: boolean = false
  @State altLatched: boolean = false

  build() {
    Row() {
      // Scrollable key buttons
      Scroll() {
        Row() {
          this.KeyButton('Esc', () => {
            this.onKeyPress('Escape')
          })

          this.LatchButton('Ctrl', this.ctrlLatched, () => {
            this.ctrlLatched = !this.ctrlLatched
          })

          this.LatchButton('Alt', this.altLatched, () => {
            this.altLatched = !this.altLatched
          })

          this.KeyButton('Tab', () => {
            this.onKeyPress('Tab')
          })

          this.KeyButton('S-Tab', () => {
            this.onKeyPress('\x1b[Z')
          })

          this.KeyButton('←', () => {
            this.onKeyPress('ArrowLeft')
          })

          this.KeyButton('↑', () => {
            this.onKeyPress('ArrowUp')
          })

          this.KeyButton('↓', () => {
            this.onKeyPress('ArrowDown')
          })

          this.KeyButton('→', () => {
            this.onKeyPress('ArrowRight')
          })

          this.KeyButton('Home', () => {
            this.onKeyPress('\x1b[H')
          })

          this.KeyButton('End', () => {
            this.onKeyPress('\x1b[F')
          })

          this.KeyButton('Copy', () => {
            if (this.onCopy) {
              this.onCopy()
            }
          })

          this.KeyButton('Paste', () => {
            this.handlePaste()
          })
        }
        .height(52)
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      // Done button - fixed to the right
      Button('完成')
        .height(44)
        .constraintSize({ minWidth: 60 })
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .margin({ left: 4, right: 4 })
        .onClick(() => {
          if (this.onDismiss) {
            this.onDismiss()
          }
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 4, right: 4 })
    .backgroundColor($r('app.color.terminal_surface_container'))
  }

  @Builder
  KeyButton(label: string, action: () => void) {
    Button(label)
      .height(44)
      .constraintSize({ minWidth: 44 })
      .borderRadius(8)
      .backgroundColor($r('app.color.terminal_surface_container_high'))
      .fontColor($r('app.color.terminal_primary'))
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        if (this.ctrlLatched) {
          this.onKeyPress(`Ctrl+${label}`)
          this.ctrlLatched = false
        } else if (this.altLatched) {
          this.onKeyPress(`Alt+${label}`)
          this.altLatched = false
        } else {
          action()
        }
      })
  }

  @Builder
  LatchButton(label: string, latched: boolean, toggle: () => void) {
    Button(label)
      .height(44)
      .constraintSize({ minWidth: 44 })
      .borderRadius(8)
      .backgroundColor(latched ?
        $r('app.color.terminal_secondary_container') :
        $r('app.color.terminal_surface_container_high'))
      .fontColor(latched ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_primary'))
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        toggle()
      })
  }

  private async handlePaste() {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const pasteData = await systemPasteboard.getData()
      const text = pasteData.getPrimaryText()
      if (text) {
        if (this.ctrlLatched) {
          this.onKeyPress(`Ctrl+${text}`)
          this.ctrlLatched = false
        } else if (this.altLatched) {
          this.onKeyPress(`Alt+${text}`)
          this.altLatched = false
        } else {
          this.onKeyPress(text)
        }
      }
    } catch (e) {
      console.warn('Paste failed: ' + (e as Error).message)
    }
  }
}
