/**
 * @file AccountSecurityPage.ets
 * @brief Account security page — change password
 */
import { RestApiClient } from '@rwecho/terminal'

@Component
export struct AccountSecurityPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State currentPassword: string = ''
  @State newPassword: string = ''
  @State confirmPassword: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  private apiClient: RestApiClient = new RestApiClient()

  build() {
    Column() {
      // Top bar
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

        Text('账号安全')
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
          // Password change section
          Text('修改密码')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_secondary'))
            .width('calc(100% - 40vp)')
            .margin({ top: 20, bottom: 8 })

          Column() {
            Text('当前密码')
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 6 })

            TextInput({ text: this.currentPassword, placeholder: '输入当前密码' })
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
            Text('新密码')
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 6 })

            TextInput({ text: this.newPassword, placeholder: '输入新密码 (最少 8 位)' })
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
            Text('确认新密码')
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 6 })

            TextInput({ text: this.confirmPassword, placeholder: '再次输入新密码' })
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

          // Error message
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_error'))
              .width('calc(100% - 40vp)')
              .margin({ bottom: 8 })
          }

          // Success message
          if (this.successMessage.length > 0) {
            Text(this.successMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_tertiary'))
              .width('calc(100% - 40vp)')
              .margin({ bottom: 8 })
          }

          // Submit button
          Button(this.isLoading ? '提交中...' : '修改密码')
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
      this.errorMessage = '请输入当前密码'
      return
    }
    if (this.newPassword.length < 8) {
      this.errorMessage = '新密码至少 8 个字符'
      return
    }
    if (this.newPassword !== this.confirmPassword) {
      this.errorMessage = '两次输入的新密码不一致'
      return
    }

    this.isLoading = true
    try {
      await this.apiClient.changePassword(this.currentPassword, this.newPassword)
      this.successMessage = '密码修改成功'
      this.currentPassword = ''
      this.newPassword = ''
      this.confirmPassword = ''
    } catch (e) {
      this.errorMessage = (e as Error).message || '修改失败，请重试'
    } finally {
      this.isLoading = false
    }
  }
}
