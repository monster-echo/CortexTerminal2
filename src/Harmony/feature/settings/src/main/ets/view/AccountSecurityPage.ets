import { common } from '@kit.AbilityKit'
import { ApiService, AuthService, AuthState, I18n, PageLayout, RouteName, showI18nToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic, heavyHaptic } from '@rwecho/core'
import { HuaweiIapService } from '../service/HuaweiIapService'

@Component
export struct AccountSecurityPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State showDeleteSheet: boolean = false
  @State confirmUsername: string = ''
  @State isDeleting: boolean = false
  @State deleteError: string = ''
  @State subscriptionWarningAccepted: boolean = false
  @State currentUsername: string = ''
  @State activeSubPlan: string = ''

  aboutToAppear() {
    AnalyticsService.onPageStart('AccountSecurity')
    this.currentUsername = AuthState.getDisplayName()
    if (this.currentUsername.length === 0) {
      this.loadProfile()
    }
    this.loadSubscriptionNotice()
  }

  private async loadProfile() {
    try {
      const profile = await ApiService.getProfile()
      this.currentUsername = (profile['username'] as string) || ''
    } catch (_e) {}
  }

  private async loadSubscriptionNotice() {
    try {
      const sub = await ApiService.getSubscription()
      const active = (sub['isActive'] as boolean) ?? false
      const planCode = (sub['planCode'] as string) ?? ''
      if (active && planCode.length > 0 && planCode !== 'pro_lifetime') {
        const key = `membership.plan_${planCode}`
        this.activeSubPlan = I18n.get(key) === key ? planCode : I18n.get(key)
      }
    } catch (_e) {}
  }

  private async manageSubscription() {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      await HuaweiIapService.manageSubscriptions(context, '')
    } catch (_e) {
      showI18nToast('membership.manage_failed')
    }
  }

  build() {
    PageLayout({ title: I18n.get('security.title') }) {
        Column() {
          // Change Password
          Row() {
            Text(I18n.get('security.change_password'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_text'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.terminal_text_muted')])
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_background_panel'))
          .margin({ bottom: 8 })
          .onClick(() => {
            lightHaptic()
            this.pageStack.pushPath({ name: RouteName.CHANGE_PASSWORD })
          })

          // Delete Account
          Row() {
            Text(I18n.get('security.delete_account'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_error'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.terminal_text_muted')])
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_background_panel'))
          .onClick(() => {
            clickHaptic()
            this.subscriptionWarningAccepted = false
            this.confirmUsername = ''
            this.deleteError = ''
            this.showDeleteSheet = true
          })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8 })
        .bindSheet(this.showDeleteSheet, this.DeleteSheetContent(), {
          height: SheetSize.MEDIUM,
          showClose: true,
          backgroundColor: $r('app.color.terminal_background'),
          onDisappear: () => { this.showDeleteSheet = false }
        })
    }
  }

  @Builder
  DeleteSheetContent() {
    Column() {
      Column() {
        Text(I18n.get('security.delete_account'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_error'))
          .width('100%')
          .margin({ bottom: 12 })

        Text(I18n.get('security.delete_desc'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_text_muted'))
          .width('100%')
          .margin({ bottom: 16 })

        if (this.activeSubPlan.length > 0) {
          Column({ space: 12 }) {
            Text(I18n.get('security.delete_active_sub').replace('{plan}', this.activeSubPlan))
              .fontSize(13)
              .fontColor($r('app.color.terminal_warning'))
              .lineHeight(20)
              .width('100%')
            Button(I18n.get('membership.manage_subscription'))
              .width('100%')
              .height(40)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .onClick(() => {
                clickHaptic()
                this.manageSubscription()
              })
          }.width('100%').margin({ bottom: 12 })
        }

        Text(I18n.get('security.subscription_cancel_warning'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_text_muted'))
          .width('100%')
          .margin({ bottom: 12 })
        Row({ space: 8 }) {
          Checkbox({ name: 'subscriptionCancelNotice', group: 'accountDeletion' })
            .select(this.subscriptionWarningAccepted)
            .onChange((value: boolean) => { this.subscriptionWarningAccepted = value })
          Text(I18n.get('security.subscription_cancel_acknowledge'))
            .fontSize(13)
            .fontColor($r('app.color.terminal_text'))
            .layoutWeight(1)
        }.width('100%').margin({ bottom: 12 })

        TextInput({ placeholder: I18n.get('security.type_username_confirm').replace('{n}', this.currentUsername), text: this.confirmUsername })
          .width('100%')
          .height(48)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_background_element'))
          .fontColor($r('app.color.terminal_text'))
          .placeholderColor($r('app.color.terminal_text_muted'))
          .onChange((value: string) => {
            this.confirmUsername = value
            this.deleteError = ''
          })

        if (this.deleteError.length > 0) {
          Text(this.deleteError)
            .fontSize(13)
            .fontColor($r('app.color.terminal_error'))
            .width('100%')
            .margin({ top: 8 })
        }

        Button() {
          if (this.isDeleting) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('app.color.terminal_background'))
          } else {
            Text(I18n.get('security.delete_button'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_background'))
          }
        }
        .width('100%')
        .height(48)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_error'))
        .margin({ top: 20 })
        .enabled(this.confirmUsername === this.currentUsername && this.subscriptionWarningAccepted && !this.isDeleting)
        .opacity(this.confirmUsername === this.currentUsername ? 1 : 0.5)
        .onClick(() => {
          heavyHaptic()
          this.deleteAccount()
        })
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
    .backgroundColor($r('app.color.terminal_background'))
  }

  private async deleteAccount() {
    this.isDeleting = true
    this.deleteError = ''
    try {
      await ApiService.deleteAccount()
      this.isDeleting = false
      this.showDeleteSheet = false
      AnalyticsService.onEvent(AnalyticsEvent.ACCOUNT_DELETE)
      showI18nToast('security.account_deleted')
      AuthService.logout()
    } catch (e) {
      this.deleteError = (e as Error).message || I18n.get('common.error')
      this.isDeleting = false
    }
  }
}
