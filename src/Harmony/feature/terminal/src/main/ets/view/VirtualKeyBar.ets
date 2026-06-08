/**
 * @file VirtualKeyBar.ets
 * @brief Single-row horizontally scrollable virtual keyboard bar
 *
 * Provides modifier keys and special keys in a single scrollable row.
 * Ctrl/Alt are sticky toggle — stay latched until manually toggled off.
 */
import { pasteboard } from '@kit.BasicServicesKit'
import { I18n } from '@rwecho/core'

type OnKeyPressCallback = (key: string) => void

@Component
struct LatchButton {
  label: string = ''
  @Prop latched: boolean = false
  onToggle: () => void = () => {}

  build() {
    Button(this.label)
      .height(36)
      .constraintSize({ minWidth: 36 })
      .borderRadius(8)
      .backgroundColor(this.latched ?
        $r('app.color.terminal_secondary_container') :
        $r('app.color.terminal_surface_container_high'))
      .fontColor(this.latched ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_primary'))
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        this.onToggle()
      })
  }
}

@Component
export struct VirtualKeyBar {
  onKeyPress: OnKeyPressCallback = (_key: string) => {}
  onDismiss: (() => void) | null = null
  onModifierChange: ((ctrl: boolean, alt: boolean) => void) | null = null
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

          LatchButton({
            label: 'Ctrl',
            latched: this.ctrlLatched,
            onToggle: () => {
              this.ctrlLatched = !this.ctrlLatched
              this.notifyModifierChange()
            }
          })

          LatchButton({
            label: 'Alt',
            latched: this.altLatched,
            onToggle: () => {
              this.altLatched = !this.altLatched
              this.notifyModifierChange()
            }
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

          this.KeyButton('Paste', () => {
            this.handlePaste()
          })
        }
        .height(44)
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      // Done button - fixed to the right
      Button(I18n.get('common.done'))
        .height(36)
        .constraintSize({ minWidth: 52 })
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .margin({ left: 4, right: 4 })
        .onClick(() => {
          if (this.onDismiss) {
            this.onDismiss()
          }
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 4, right: 4 })
    .backgroundColor($r('app.color.terminal_surface_container'))
  }

  private notifyModifierChange() {
    if (this.onModifierChange) {
      this.onModifierChange(this.ctrlLatched, this.altLatched)
    }
  }

  @Builder
  KeyButton(label: string, action: () => void) {
    Button(label)
      .height(36)
      .constraintSize({ minWidth: 36 })
      .borderRadius(8)
      .backgroundColor($r('app.color.terminal_surface_container_high'))
      .fontColor($r('app.color.terminal_primary'))
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        if (this.ctrlLatched) {
          this.onKeyPress(`Ctrl+${label}`)
        } else if (this.altLatched) {
          this.onKeyPress(`Alt+${label}`)
        } else {
          action()
        }
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
        } else if (this.altLatched) {
          this.onKeyPress(`Alt+${text}`)
        } else {
          this.onKeyPress(text)
        }
      }
    } catch (e) {
      console.warn('Paste failed: ' + (e as Error).message)
    }
  }
}
