import { SessionInfo, I18n } from '@rwecho/core'
import { TimeUtils } from '../utils/TimeUtils'

@Component
export struct SessionCard {
  @Prop session: SessionInfo = new SessionInfo()
  onResume?: (session: SessionInfo) => void
  onDelete?: (session: SessionInfo) => void
  showResumeButton: boolean = true

  build() {
    Row() {
      // Status chip
      Row() {
        Circle().width(8).height(8).fill(this.getStatusColor())
        Text(this.getStatusLabel())
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ left: 6 })
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(8)
      .backgroundColor($r('app.color.terminal_surface_container'))

      Blank()

      // Session info
      Column() {
        Text(this.session.name || `session ${this.session.id.substring(0, 8)}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.session.workerName.length > 0) {
          Text(this.session.workerName)
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 2 })
        }

        Text(TimeUtils.formatRelativeTime(this.session.updatedAt || this.session.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)
      .layoutWeight(1)

      // Resume button (only for active sessions)
      if (this.showResumeButton) {
        Button(I18n.get('session.card.resume'))
          .height(32)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .fontSize(13)
          .margin({ left: 12 })
          .onClick(() => {
            if (this.onResume) this.onResume(this.session)
          })
      }

      // Delete button
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(16)
          .fontColor([$r('app.color.terminal_error')])
      }
      .width(32)
      .height(32)
      .borderRadius(8)
      .backgroundColor(Color.Transparent)
      .margin({ left: 6 })
      .onClick(() => {
        this.confirmDelete()
      })
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ bottom: 8 })
  }

  private getStatusColor(): ResourceColor {
    switch (this.session.status.toLowerCase()) {
      case 'live':
      case 'connected':
      case 'running':
        return $r('app.color.terminal_tertiary')
      case 'reconnecting':
      case 'connecting':
        return '#FFC107'
      case 'expired':
      case 'failed':
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_outline_variant')
    }
  }

  private getStatusLabel(): string {
    switch (this.session.status.toLowerCase()) {
      case 'live':
      case 'connected':
      case 'running':
        return I18n.get('session.status.live')
      case 'idle':
      case 'detached':
        return I18n.get('session.status.detached')
      case 'expired':
        return I18n.get('session.status.expired')
      case 'exited':
        return I18n.get('session.status.exited')
      default:
        return this.session.status
    }
  }

  private confirmDelete() {
    AlertDialog.show({
      title: I18n.get('session.card.delete_confirm_title'),
      message: I18n.get('session.card.delete_confirm_message'),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('common.delete'),
        fontColor: $r('app.color.terminal_error'),
        action: () => {
          if (this.onDelete) this.onDelete(this.session)
        }
      }
    })
  }
}
