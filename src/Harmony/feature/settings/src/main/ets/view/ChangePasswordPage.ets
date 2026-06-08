import { ApiService, I18n, PageLayout, showI18nToast, AnalyticsService, AnalyticsEvent } from '@rwecho/core'

@Component
export struct ChangePasswordPage {
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('ChangePassword')
  }

  @State currentPassword: string = ''
  @State newPassword: string = ''
  @State confirmPassword: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''

  build() {
    PageLayout({ title: I18n.get('security.change_password') }) {
        Column() {
          Column() {
            Text(I18n.get('security.current_password'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 6 })

            TextInput({ text: this.currentPassword, placeholder: I18n.get('security.current_password') })
              .type(InputType.Password)
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
              .fontColor($r('app.color.terminal_primary'))
              .placeholderColor($r('app.color.terminal_on_surface_variant'))
              .onChange((value: string) => {
                this.currentPassword = value
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ bottom: 8 })

          Column() {
            Text(I18n.get('security.new_password'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 6 })

            TextInput({ text: this.newPassword, placeholder: I18n.get('security.new_password') })
              .type(InputType.Password)
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
              .fontColor($r('app.color.terminal_primary'))
              .placeholderColor($r('app.color.terminal_on_surface_variant'))
              .onChange((value: string) => {
                this.newPassword = value
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ bottom: 8 })

          Column() {
            Text(I18n.get('security.confirm_password'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 6 })

            TextInput({ text: this.confirmPassword, placeholder: I18n.get('security.confirm_password') })
              .type(InputType.Password)
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
              .fontColor($r('app.color.terminal_primary'))
              .placeholderColor($r('app.color.terminal_on_surface_variant'))
              .onChange((value: string) => {
                this.confirmPassword = value
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ bottom: 8 })

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_error'))
              .width('100%')
              .margin({ bottom: 8 })
          }

          if (this.successMessage.length > 0) {
            Text(this.successMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_tertiary'))
              .width('100%')
              .margin({ bottom: 8 })
          }

          Button(I18n.get('security.submit'))
            .width('100%')
            .height(48)
            .borderRadius(12)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 8 })
            .enabled(!this.isLoading)
            .onClick(() => {
              this.submitChangePassword()
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8 })
    }
  }

  private async submitChangePassword() {
    this.errorMessage = ''
    this.successMessage = ''

    if (this.currentPassword.length === 0) {
      this.errorMessage = I18n.get('security.current_password')
      return
    }
    if (this.newPassword.length === 0) {
      this.errorMessage = I18n.get('security.new_password')
      return
    }
    if (this.newPassword !== this.confirmPassword) {
      this.errorMessage = I18n.get('security.password_mismatch')
      return
    }

    this.isLoading = true
    try {
      await ApiService.changePassword(this.currentPassword, this.newPassword)
      this.successMessage = I18n.get('security.change_password') + ' ✓'
      AnalyticsService.onEvent(AnalyticsEvent.PASSWORD_CHANGE)
      showI18nToast('security.password_changed')
      this.currentPassword = ''
      this.newPassword = ''
      this.confirmPassword = ''
    } catch (e) {
      this.errorMessage = (e as Error).message || I18n.get('common.error')
    } finally {
      this.isLoading = false
    }
  }
}
