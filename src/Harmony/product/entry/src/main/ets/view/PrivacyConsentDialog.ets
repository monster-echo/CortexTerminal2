/**
 * @file PrivacyConsentDialog.ets
 * @brief 首次启动隐私协议弹窗：同意前不采集数据、不进入应用（华为审核硬性要求）。
 */
import { I18n } from '@rwecho/core'

@CustomDialog
export struct PrivacyConsentDialog {
  controller?: CustomDialogController
  onAgree: () => void = () => {}
  onDisagree: () => void = () => {}
  openDoc: (kind: string) => void = () => {}

  build() {
    Column() {
      Text(I18n.get('privacy.consent.title'))
        .fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_text'))
        .margin({ top: 24 })

      Scroll() {
        Text() {
          Span(I18n.get('privacy.consent.body_prefix'))
            .fontColor($r('app.color.terminal_text_muted'))
          Span(`《${I18n.get('settings.footer_terms')}》`)
            .fontColor($r('app.color.terminal_on_primary_container'))
            .onClick(() => { this.openDoc('terms') })
          Span(I18n.get('privacy.consent.body_middle'))
            .fontColor($r('app.color.terminal_text_muted'))
          Span(`《${I18n.get('settings.footer_privacy')}》`)
            .fontColor($r('app.color.terminal_on_primary_container'))
            .onClick(() => { this.openDoc('privacy') })
          Span(I18n.get('privacy.consent.body_suffix'))
            .fontColor($r('app.color.terminal_text_muted'))
        }.fontSize(14).lineHeight(22)
      }.constraintSize({ maxHeight: 260 }).margin({ top: 16 })
      .align(Alignment.Top)

      Button(I18n.get('privacy.consent.agree'))
        .width('100%').height(48).fontSize(16).fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.terminal_inverse_surface'))
        .fontColor($r('app.color.terminal_inverse_on_surface'))
        .margin({ top: 20 })
        .onClick(() => { this.controller?.close(); this.onAgree() })

      Button(I18n.get('privacy.consent.disagree'))
        .width('100%').height(48).fontSize(14)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .margin({ top: 8, bottom: 24 })
        .onClick(() => { this.controller?.close(); this.onDisagree() })
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
  }
}
