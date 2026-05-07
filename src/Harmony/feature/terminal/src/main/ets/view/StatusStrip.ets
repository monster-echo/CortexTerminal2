/**
 * @file StatusStrip.ets
 * @brief Connection state indicator bar
 *
 * Displays the current terminal connection state with a colored
 * indicator dot and text label. Shows a spinner during reconnection.
 */
import { TerminalState } from '../model/TerminalState'

@Component
export struct StatusStrip {
  @Prop currentState: TerminalState = TerminalState.Disconnected

  build() {
    Row() {
      // State indicator dot
      Row() {
        Circle()
          .width(8)
          .height(8)
          .fill(this.getIndicatorColor())

        // Spinner for reconnecting state
        if (this.currentState === TerminalState.Reconnecting) {
          LoadingProgress()
            .width(12)
            .height(12)
            .color(this.getIndicatorColor())
            .margin({ left: 4 })
        }
      }

      // State text
      Text(this.getStateLabel())
        .fontSize(12)
        .fontColor(this.getTextColor())
        .margin({ left: 8 })
    }
    .width('100%')
    .height(28)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.getBackgroundColor())
    .alignItems(VerticalAlign.Center)
  }

  private getStateLabel(): string {
    switch (this.currentState) {
      case TerminalState.Disconnected:
        return 'Disconnected'
      case TerminalState.Connecting:
        return 'Connecting...'
      case TerminalState.Replaying:
        return 'Replaying session...'
      case TerminalState.Live:
        return 'Connected'
      case TerminalState.Reconnecting:
        return 'Reconnecting...'
      case TerminalState.Detached:
        return 'Detached'
      case TerminalState.Expired:
        return 'Session Expired'
      case TerminalState.Exited:
        return 'Process Exited'
      case TerminalState.Error:
        return 'Connection Error'
      default:
        return 'Unknown'
    }
  }

  private getIndicatorColor(): ResourceColor {
    switch (this.currentState) {
      case TerminalState.Live:
        return $r('app.color.terminal_tertiary')
      case TerminalState.Connecting:
      case TerminalState.Reconnecting:
        return '#FFC107'
      case TerminalState.Replaying:
        return '#2196F3'
      case TerminalState.Detached:
      case TerminalState.Exited:
        return $r('app.color.terminal_outline_variant')
      case TerminalState.Expired:
      case TerminalState.Error:
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_outline_variant')
    }
  }

  private getTextColor(): ResourceColor {
    switch (this.currentState) {
      case TerminalState.Live:
        return $r('app.color.terminal_tertiary')
      case TerminalState.Expired:
      case TerminalState.Error:
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_on_surface_variant')
    }
  }

  private getBackgroundColor(): ResourceColor {
    switch (this.currentState) {
      case TerminalState.Expired:
      case TerminalState.Error:
        return '#1AFF4444'
      default:
        return $r('app.color.terminal_surface_container')
    }
  }
}
