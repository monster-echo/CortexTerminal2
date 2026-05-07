/**
 * @file VirtualKeyBar.ets
 * @brief Collapsible virtual keyboard bar for terminal input
 *
 * Provides modifier keys (Esc, Ctrl latch, Alt latch, Tab, Paste)
 * and an expandable row with arrow keys. All touch targets meet
 * the 44px minimum accessibility requirement.
 */
import { pasteboard } from '@kit.BasicServicesKit'

/**
 * Callback type for virtual key press events.
 */
type OnKeyPressCallback = (key: string) => void

/**
 * Callback type for expand toggle events.
 */
type OnToggleExpandCallback = () => void

@Component
export struct VirtualKeyBar {
  @Prop onKeyPress: OnKeyPressCallback = (_key: string) => {}
  @Prop onToggleExpand: OnToggleExpandCallback = () => {}
  @State expanded: boolean = false
  @State ctrlLatched: boolean = false
  @State altLatched: boolean = false

  build() {
    Column() {
      // Main key row
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

        this.KeyButton('Paste', () => {
          this.handlePaste()
        })

        // Expand/collapse toggle
        Button() {
          Text(this.expanded ? '▼' : '▲')
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
        }
        .width(44)
        .height(44)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .onClick(() => {
          this.onToggleExpand()
        })
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ left: 4, right: 4 })
      .backgroundColor($r('app.color.terminal_surface_container'))

      // Expandable arrow key row
      if (this.expanded) {
        Row() {
          this.KeyButton('↑', () => {
            this.onKeyPress('ArrowUp')
          })

          this.KeyButton('↓', () => {
            this.onKeyPress('ArrowDown')
          })

          this.KeyButton('←', () => {
            this.onKeyPress('ArrowLeft')
          })

          this.KeyButton('→', () => {
            this.onKeyPress('ArrowRight')
          })

          // Home and End
          this.KeyButton('Home', () => {
            this.onKeyPress('\x1b[H')
          })

          this.KeyButton('End', () => {
            this.onKeyPress('\x1b[F')
          })
        }
        .width('100%')
        .height(52)
        .justifyContent(FlexAlign.SpaceEvenly)
        .padding({ left: 4, right: 4 })
        .backgroundColor($r('app.color.terminal_surface_container'))
      }
    }
    .width('100%')
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
      .onClick(() => {
        toggle()
      })
  }

  private async handlePaste() {
    // Read from the system clipboard using @ohos.pasteboard
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
