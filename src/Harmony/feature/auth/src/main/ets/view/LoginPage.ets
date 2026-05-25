/**
 * @file LoginPage.ets
 * @brief Login page with Huawei one-click login as hero action.
 *
 * "Other login methods" navigates to PasswordLoginPage (separate route).
 * No agreement checkbox — Huawei system button handles agreement internally.
 */
import { AuthService } from '../service/AuthService'
import { loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit'
import { BusinessError } from '@kit.BasicServicesKit'

@Component
export struct LoginPage {
  @State isHuaweiLoading: boolean = false
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  private authService: AuthService = new AuthService()

  private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError | undefined,
         response: loginComponentManager.HuaweiIDCredential) => {
          if (error) {
            if (error.code !== 1001502012 && error.code !== 1001502001) {
              this.errorMessage = $r('app.string.login_error_huawei_failed')
            }
            return
          }
          if (response) {
            const authCode = response.authorizationCode ?? ''
            const openID = response.openID ?? ''
            const unionID = response.unionID ?? ''
            if (authCode.length === 0) {
              this.errorMessage = $r('app.string.login_error_no_code')
              return
            }
            this.handleHuaweiLogin(authCode, unionID, openID)
          }
        }
      )

  build() {
    Scroll() {
      Column() {
        // Brand Identity
        Column() {
          Image($r('app.media.app_icon'))
            .width(96)
            .height(96)
            .borderRadius(24)
            .margin({ bottom: 18 })

          Text($r('app.string.app_name'))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))

          Text($r('app.string.login_tagline'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 80 })

        // Huawei Login Button (hero action)
        Stack() {
          LoginWithHuaweiIDButton({
            params: {
              style: loginComponentManager.Style.BUTTON_RED,
              loginType: loginComponentManager.LoginType.QUICK_LOGIN,
              borderRadius: 24,
              supportDarkMode: true
            },
            controller: this.huaweiButtonController
          }).width('100%').height(48).constraintSize({ maxWidth: 400 })

          if (this.isHuaweiLoading) {
            Row() {
              LoadingProgress()
                .width(24)
                .height(24)
                .color($r('app.color.terminal_primary'))
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.terminal_surface_container'))
            .opacity(0.7)
            .borderRadius(24)
            .constraintSize({ maxWidth: 400 })
            .hitTestBehavior(HitTestMode.Block)
          }
        }
        .width('100%')
        .alignContent(Alignment.Center)
        .padding({ left: 24, right: 24 })
        .margin({ top: 48 })

        // Other login methods
        Text($r('app.string.login_other_method'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_secondary'))
          .margin({ top: 24 })
          .onClick(() => {
            this.pageStack.pushPath({ name: 'PasswordLogin' })
          })

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
          .padding({ left: 24, right: 24 })
          .margin({ top: 16 })
        }

        Blank()
          .height(24)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
    .scrollBar(BarState.Off)
  }

  private async handleHuaweiLogin(authCode: string, unionID: string, openID: string) {
    this.isHuaweiLoading = true
    this.errorMessage = ''
    try {
      await this.authService.loginWithHuaweiAuthCode(authCode, unionID, openID)
      this.isHuaweiLoading = false
      AuthService.navigateHome(this.pageStack)
    } catch (err) {
      this.errorMessage = (err as Error).message || $r('app.string.login_error_huawei_failed') as string
      this.isHuaweiLoading = false
    }
  }
}
