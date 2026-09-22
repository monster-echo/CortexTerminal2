/**
 * @file AnnouncementDialog.ets
 * @brief Centered announcement dialog driven by gateway-served content.
 *
 * Title / body / primary button label all come from /api/announcements.
 * Parent decides dismiss + navigation via callbacks; both buttons dismiss
 * the announcement (每条公告只弹一次).
 */
import { AnnouncementInfo } from '../model/SharedModels'
import { clickHaptic } from '../utils/HapticUtils'
import { I18n } from '../i18n/I18n'

@CustomDialog
export struct AnnouncementDialog {
  controller: CustomDialogController
  announcement: AnnouncementInfo = new AnnouncementInfo()
  onJoin: (url: string) => void = (_url: string) => {}
  onDismiss: () => void = () => {}

  build() {
    Column() {
      Text(this.announcement.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_on_surface'))
        .width('100%')

      Text(this.announcement.body)
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .lineHeight(22)
        .width('100%')
        .margin({ top: 12 })

      Button(this.announcement.buttonLabel)
        .type(ButtonType.Capsule)
        .height(44)
        .width('100%')
        .backgroundColor($r('app.color.terminal_primary'))
        .fontColor($r('app.color.terminal_on_primary'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 24 })
        .onClick(() => {
          clickHaptic()
          this.onJoin(this.announcement.url)
          this.onDismiss()
          this.controller.close()
        })

      Button(I18n.get('announcement.later'))
        .type(ButtonType.Capsule)
        .height(40)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .fontSize(14)
        .margin({ top: 8 })
        .onClick(() => {
          clickHaptic()
          this.onDismiss()
          this.controller.close()
        })
    }
    .padding(24)
    .borderRadius(16)
    .backgroundColor($r('app.color.terminal_surface_container_highest'))
    .width('80%')
    .constraintSize({ maxWidth: 320 })
  }
}
