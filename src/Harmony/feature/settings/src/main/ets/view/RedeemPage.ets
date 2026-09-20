/**
 * @file RedeemPage.ets
 * @brief Redeem a membership code (POST /api/billing/redeem).
 *
 * Pushed from the Membership page "···" menu. On success the membership
 * entitlement is refreshed via the membershipRefreshTick AppStorage signal
 * and the page pops back.
 */
import {
  ApiService,
  I18n,
  PageLayout,
  showI18nToast,
  showToast,
  clickHaptic
} from '@rwecho/core'

@Component
export struct RedeemPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State redeemCodeInput: string = ''
  @State isRedeeming: boolean = false

  private async redeem() {
    const code = this.redeemCodeInput.trim()
    if (code.length === 0) {
      return
    }
    this.isRedeeming = true
    try {
      await ApiService.redeemCode(code)
      showI18nToast('membership.redeem_success')
      AppStorage.setOrCreate('membershipRefreshTick', Date.now())
      this.redeemCodeInput = ''
      this.pageStack.pop()
    } catch (e) {
      showToast(I18n.getWithArgs('membership.redeem_failed', { 'msg': (e as Error).message }))
    } finally {
      this.isRedeeming = false
    }
  }

  build() {
    PageLayout({ title: I18n.get('membership.menu_redeem') }) {
      Column() {
        TextInput({ placeholder: I18n.get('membership.redeem_placeholder'), text: this.redeemCodeInput })
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .borderRadius(8)
          .fontColor($r('app.color.terminal_primary'))
          .placeholderColor($r('app.color.terminal_on_surface_variant'))
          .onChange((value: string) => {
            this.redeemCodeInput = value
          })

        Button(this.isRedeeming ? '…' : I18n.get('membership.redeem_button'))
          .type(ButtonType.Capsule)
          .width('100%')
          .height(48)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 16 })
          .enabled(this.redeemCodeInput.trim().length > 0 && !this.isRedeeming)
          .opacity(this.redeemCodeInput.trim().length > 0 && !this.isRedeeming ? 1 : 0.5)
          .onClick(() => {
            clickHaptic()
            this.redeem()
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8 })
    }
  }
}
