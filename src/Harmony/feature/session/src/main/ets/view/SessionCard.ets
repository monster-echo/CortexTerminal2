import { SessionInfo, I18n } from '@rwecho/core'
import { TimeUtils } from '../utils/TimeUtils'

@Component
export struct SessionCard {
  @Prop workspaceStyle: boolean = false
  @Prop session: SessionInfo = new SessionInfo()
  onCardClick?: () => void

  build() {
    Row() {
      if (this.workspaceStyle) {
        Image($r('app.media.ws_terminal')).width(22).height(22).fillColor($r('app.color.terminal_text')).margin({ right: 12 })
      }
      // Session info
      Column() {
        Text(this.session.name || `session ${this.session.id.substring(0, 8)}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!this.workspaceStyle && this.session.workerName.length > 0) {
          Text(this.session.workerName)
            .fontSize(12)
            .fontColor($r('app.color.terminal_text_muted'))
            .margin({ top: 2 })
        }

        Text(TimeUtils.formatRelativeTime(this.session.updatedAt || this.session.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // Status chip
      Row() {
        Circle().width(8).height(8).fill(this.getStatusColor())
        Text(this.getStatusLabel())
          .fontSize(11)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ left: 6 })
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(8)
      .backgroundColor($r('app.color.terminal_background_panel'))
    }
    .width('100%')
    .padding(this.workspaceStyle ? 16 : 14)
    .constraintSize({ minHeight: this.workspaceStyle ? 80 : 0 })
    .border({ width: this.workspaceStyle ? 1 : 0, color: $r('app.color.terminal_border_subtle') })
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_background_panel'))
    .onClick(() => { if (this.onCardClick) { this.onCardClick() } })
  }

  private getStatusColor(): ResourceColor {
    switch (this.session.status.toLowerCase()) {
      case 'live':
      case 'connected':
      case 'running':
        return $r('app.color.terminal_success')
      case 'reconnecting':
      case 'connecting':
        return $r('app.color.terminal_warning')
      case 'expired':
      case 'failed':
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_status_idle')
    }
  }

  private getStatusLabel(): string {
    switch (this.session.status.toLowerCase()) {
      case 'live':
      case 'connected':
      case 'running':
        return I18n.get('workspace.ui.running')
      case 'idle':
      case 'detached':
        return I18n.get('workspace.ui.idle')
      case 'expired':
        return 'Expired'
      case 'exited':
        return 'Exited'
      default:
        return this.session.status
    }
  }
}
