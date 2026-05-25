/**
 * @file PasswordLoginPage.ets
 * @brief Username/password login page (secondary, navigated from LoginPage).
 *
 * Agreement handled as "login = consent" text at bottom.
 */
import { AuthService } from '../service/AuthService'
import { common, Want } from '@kit.AbilityKit'

@Component
export struct PasswordLoginPage {
  @State username: string = ''
  @State password: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  private authService: AuthService = new AuthService()

  build() {
    NavDestination() {
      Column() {
        // Form card
        Column() {
          Text($r('app.string.login_username_label'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .width('100%')
            .margin({ bottom: 8 })

          TextInput({ placeholder: $r('app.string.login_username_placeholder'), text: this.username })
            .width('100%')
            .height(48)
            .borderRadius(8)
            .backgroundColor($r('app.color.terminal_surface_container_high'))
            .fontColor($r('app.color.terminal_primary'))
            .placeholderColor($r('app.color.terminal_on_surface_variant'))
            .onChange((value: string) => {
              this.username = value
              this.errorMessage = ''
            })

          Text($r('app.string.login_password_label'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .width('100%')
            .margin({ top: 16, bottom: 8 })

          TextInput({ placeholder: $r('app.string.login_password_placeholder'), text: this.password })
            .type(InputType.Password)
            .width('100%')
            .height(48)
            .borderRadius(8)
            .backgroundColor($r('app.color.terminal_surface_container_high'))
            .fontColor($r('app.color.terminal_primary'))
            .placeholderColor($r('app.color.terminal_on_surface_variant'))
            .onChange((value: string) => {
              this.password = value
              this.errorMessage = ''
            })

          Button() {
            if (this.isLoading) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color($r('app.color.terminal_on_secondary_container'))
            } else {
              Text($r('app.string.login_password_button'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.terminal_on_secondary_container'))
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .margin({ top: 20 })
          .enabled(!this.isLoading && this.username.length > 0 && this.password.length > 0)
          .onClick(() => {
            this.handleLogin()
          })
        }
        .width('100%')
        .padding(20)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ top: 24 })

        // Error banner
        if (this.errorMessage.length > 0) {
          Row() {
            Text('⚠')
              .fontSize(14)
              .fontColor($r('app.color.terminal_error'))
              .margin({ right: 8 })
            Text(this.errorMessage)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_error'))
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 16 })
        }

        Blank()

        // Agreement text
        Text() {
          Span($r('app.string.login_agreement_prefix'))
            .fontColor($r('app.color.terminal_on_surface_variant'))
          Span($r('app.string.login_agreement_terms'))
            .fontColor($r('app.color.terminal_secondary'))
            .onClick(() => {
              this.openExternal('https://gateway.ct.rwecho.top/terms')
            })
          Span(' ' + $r('app.string.login_agreement_privacy'))
            .fontColor($r('app.color.terminal_secondary'))
            .onClick(() => {
              this.openExternal('https://gateway.ct.rwecho.top/privacy')
            })
        }
        .fontSize(12)
        .margin({ top: 16, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })
    }
    .title($r('app.string.login_password_title'))
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private async handleLogin() {
    if (this.username.length === 0 || this.password.length === 0) {
      this.errorMessage = $r('app.string.login_error_empty_fields') as string
      return
    }

    this.isLoading = true
    this.errorMessage = ''
    try {
      await this.authService.loginWithPassword(this.username, this.password)
      this.isLoading = false
      AuthService.navigateHome(this.pageStack)
    } catch (err) {
      this.errorMessage = (err as Error).message || $r('app.string.login_error_login_failed') as string
      this.isLoading = false
    }
  }

  private async openExternal(url: string) {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const want = new Want()
      want.action = 'ohos.want.action.viewData'
      want.uri = url
      await context.startAbility(want)
    } catch (e) {
      console.warn('Failed to open link: ' + (e as Error).message)
    }
  }
}
