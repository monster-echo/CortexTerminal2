/**
 * @file VirtualKeyBar.ets
 * @brief Single-row horizontally scrollable virtual keyboard bar
 *
 * Provides modifier keys and special keys in a single scrollable row.
 * Ctrl/Alt are sticky toggle — stay latched until manually toggled off.
 */
import { pasteboard } from '@kit.BasicServicesKit'
import { I18n, lightHaptic, clickHaptic, TerminalChrome } from '@rwecho/core'

type OnKeyPressCallback = (key: string) => void
type OnPasteTextCallback = (text: string) => void

@Component
struct LatchButton {
  label: string = ''
  @Prop latched: boolean = false
  onToggle: () => void = () => {}
  @StorageLink('terminalChromeJson') chromeJson: string = ''

  private chrome(): TerminalChrome {
    return TerminalChrome.fromJson(this.chromeJson)
  }

  build() {
    Button(this.label)
      .height(36)
      .constraintSize({ minWidth: 36 })
      .borderRadius(8)
      .backgroundColor(this.latched ?
        this.chrome().accentContainer :
        this.chrome().surfaceHigh)
      .fontColor(this.latched ?
        this.chrome().onAccentContainer :
        this.chrome().accent)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        clickHaptic()
        this.onToggle()
      })
  }
}

@Component
export struct VirtualKeyBar {
  onKeyPress: OnKeyPressCallback = (_key: string) => {}
  // Plain paste from the system pasteboard — routed through xterm's paste so
  // bracketed-paste mode is honored for programs that opt in.
  onPasteText: OnPasteTextCallback = (_text: string) => {}
  onDismiss: (() => void) | null = null
  onModifierChange: ((ctrl: boolean, alt: boolean) => void) | null = null
  @State ctrlLatched: boolean = false
  @State altLatched: boolean = false
  @StorageLink('terminalChromeJson') chromeJson: string = ''

  private chrome(): TerminalChrome {
    return TerminalChrome.fromJson(this.chromeJson)
  }

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
        .backgroundColor(this.chrome().accentContainer)
        .fontColor(this.chrome().onAccentContainer)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .margin({ left: 4, right: 4 })
        .onClick(() => {
          clickHaptic()
          if (this.onDismiss) {
            this.onDismiss()
          }
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 4, right: 4 })
    .backgroundColor(this.chrome().surface)
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
      .backgroundColor(this.chrome().surfaceHigh)
      .fontColor(this.chrome().accent)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        lightHaptic()
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
          this.onPasteText(text)
        }
      }
    } catch (e) {
      console.warn('Paste failed: ' + (e as Error).message)
    }
  }
}
