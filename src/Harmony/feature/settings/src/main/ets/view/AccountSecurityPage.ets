import { ApiService, I18n } from '@rwecho/core'

@Component
export struct AccountSecurityPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State currentPassword: string = ''
  @State newPassword: string = ''
  @State confirmPassword: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''

  build() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.pageStack.pop()
        })

        Text(I18n.get('security.title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
          .margin({ left: 8 })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Text(I18n.get('security.change_password'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_secondary'))
            .width('calc(100% - 40vp)')
            .margin({ top: 20, bottom: 8 })

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
              .backgroundColor($r('app.color.terminal_surface_container'))
              .fontColor($r('app.color.terminal_primary'))
              .onChange((value: string) => {
                this.currentPassword = value
              })
          }
          .width('calc(100% - 40vp)')
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

            TextInput({ text: this.newPassword, placeholder: I18n.get('security.password_min_length') })
              .type(InputType.Password)
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_surface_container'))
              .fontColor($r('app.color.terminal_primary'))
              .onChange((value: string) => {
                this.newPassword = value
              })
          }
          .width('calc(100% - 40vp)')
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
              .backgroundColor($r('app.color.terminal_surface_container'))
              .fontColor($r('app.color.terminal_primary'))
              .onChange((value: string) => {
                this.confirmPassword = value
              })
          }
          .width('calc(100% - 40vp)')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ bottom: 8 })

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_error'))
              .width('calc(100% - 40vp)')
              .margin({ bottom: 8 })
          }

          if (this.successMessage.length > 0) {
            Text(this.successMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_tertiary'))
              .width('calc(100% - 40vp)')
              .margin({ bottom: 8 })
          }

          Button(I18n.get('security.submit'))
            .width('calc(100% - 40vp)')
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

          Blank().height(40)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private async submitChangePassword() {
    this.errorMessage = ''
    this.successMessage = ''

    if (this.currentPassword.length === 0) {
      this.errorMessage = I18n.get('security.current_password')
      return
    }
    if (this.newPassword.length < 8) {
      this.errorMessage = I18n.get('security.password_min_length')
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
