/**
 * @file LoginPage.ets
 * @brief Phone login page with Huawei one-click login
 *
 * Provides phone number input and verification code entry,
 * plus Huawei Account Kit one-click login.
 */
import { AuthService } from '../service/AuthService'
import { authentication, loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'

@Component
export struct LoginPage {
  @State phoneNumber: string = ''
  @State verifyCode: string = ''
  @State codeSent: boolean = false
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State countdown: number = 0
  @State quickLoginAnonymousPhone: string = ''
  @State huaweiLoginAvailable: boolean = false
  @State showPhoneLogin: boolean = false
  private authService: AuthService = new AuthService()
  private countdownTimer: number = -1

  // Huawei login button controller
  private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError | undefined,
         response: loginComponentManager.HuaweiIDCredential) => {
          console.info(`Huawei login callback: error=${JSON.stringify(error)}, response=${JSON.stringify(response)}`)
          if (error) {
            console.error(`Huawei login failed: code=${error.code}, message=${error.message}`)
            if (error.code !== 1001502012 && error.code !== 1001502001) {
              this.errorMessage = `Huawei login failed (${error.code})`
            }
            return
          }
          if (response) {
            const authCode = response.authorizationCode ?? ''
            const openID = response.openID ?? ''
            const unionID = response.unionID ?? ''
            console.info(`Huawei login: authCode=${authCode.substring(0, 10)}..., openID=${openID}, unionID=${unionID}`)
            if (authCode.length === 0) {
              this.errorMessage = 'Failed to get authorization code'
              return
            }
            this.handleHuaweiLogin(authCode, unionID, openID)
          } else {
            console.warn('Huawei login: response is null, no action taken')
          }
        }
      )

  aboutToAppear() {
    this.tryGetAnonymousPhone()
  }

  aboutToDisappear() {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer)
    }
  }

  build() {
    Column() {
      // Logo and title
      Column() {
        Text($r('app.string.app_name'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))

        Text('Connect to your terminal anywhere')
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 60 })

      // Huawei one-click login section
      if (this.huaweiLoginAvailable) {
        Column() {
          if (this.quickLoginAnonymousPhone.length > 0) {
            Text(`${this.quickLoginAnonymousPhone}`)
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ bottom: 16 })
          }

          LoginWithHuaweiIDButton({
            params: {
              style: loginComponentManager.Style.BUTTON_RED,
              loginType: loginComponentManager.LoginType.QUICK_LOGIN,
              borderRadius: 24,
              supportDarkMode: true
            },
            controller: this.huaweiButtonController
          }).width('100%').height(48).constraintSize({ maxWidth: 400 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ top: 32 })

        // Divider
        Row() {
          Divider()
            .layoutWeight(1)
            .color($r('app.color.terminal_outline_variant'))
          Text(' or ')
            .fontSize(13)
            .fontColor($r('app.color.terminal_on_surface_variant'))
          Divider()
            .layoutWeight(1)
            .color($r('app.color.terminal_outline_variant'))
        }
        .width('calc(100% - 48vp)')
        .margin({ top: 24, bottom: 8 })
      }

      // Phone number input (fallback)
      if (!this.huaweiLoginAvailable || this.showPhoneLogin) {
        Column() {
          Text('Phone Number')
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .width('100%')
            .margin({ bottom: 8 })

          TextInput({ placeholder: '13800138000', text: this.phoneNumber })
            .type(InputType.PhoneNumber)
            .maxLength(11)
            .width('100%')
            .height(48)
            .borderRadius(12)
            .backgroundColor($r('app.color.terminal_surface_container'))
            .fontColor($r('app.color.terminal_primary'))
            .placeholderColor($r('app.color.terminal_on_surface_variant'))
            .onChange((value: string) => {
              this.phoneNumber = value
              this.errorMessage = ''
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .margin({ top: 24 })
      }

      // Verification code input (shown after code sent)
      if (this.codeSent) {
        Column() {
          Text('Verification Code')
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            TextInput({ placeholder: '6-digit code', text: this.verifyCode })
              .type(InputType.Number)
              .maxLength(6)
              .width('100%')
              .height(48)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_surface_container'))
              .fontColor($r('app.color.terminal_primary'))
              .placeholderColor($r('app.color.terminal_on_surface_variant'))
              .onChange((value: string) => {
                this.verifyCode = value
                this.errorMessage = ''
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .margin({ top: 16 })
      }

      // Error message
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor($r('app.color.terminal_error'))
          .width('100%')
          .padding({ left: 24, right: 24 })
          .margin({ top: 12 })
      }

      // Primary action button
      Button(this.codeSent ? 'Verify & Login' : 'Send Verification Code')
        .width('calc(100% - 48vp)')
        .height(48)
        .margin({ top: 24 })
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor('#ffffff')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .enabled(!this.isLoading && this.phoneNumber.length === 11 &&
          (!this.codeSent || this.verifyCode.length >= 6))
        .onClick(() => {
          this.handlePrimaryAction()
        })

      // Countdown / resend
      if (this.countdown > 0) {
        Text(`Resend in ${this.countdown}s`)
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 12 })
      } else if (this.codeSent) {
        Text('Resend Code')
          .fontSize(13)
          .fontColor($r('app.color.terminal_secondary'))
          .margin({ top: 12 })
          .onClick(() => {
            this.sendCode()
          })
      }

      // Show phone login link (only when Huawei login is active and phone is hidden)
      if (this.huaweiLoginAvailable && !this.showPhoneLogin) {
        Text('Use phone number instead')
          .fontSize(14)
          .fontColor($r('app.color.terminal_secondary'))
          .margin({ top: 16 })
          .onClick(() => {
            this.showPhoneLogin = true
          })
      }

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  /**
   * Try to silently get the masked phone number from Huawei Account Kit.
   * If available, show the one-click login button.
   */
  private async tryGetAnonymousPhone() {
    try {
      const huaweiIDProvider = new authentication.HuaweiIDProvider()
      const authRequest = huaweiIDProvider.createAuthorizationWithHuaweiIDRequest()
      authRequest.scopes = ['quickLoginAnonymousPhone']
      authRequest.state = util.generateRandomUUID()
      authRequest.forceAuthorization = false

      const controller = new authentication.AuthenticationController()
      const response: authentication.AuthorizationWithHuaweiIDResponse =
        await controller.executeRequest(authRequest)

      const anonymousPhone = response.data?.extraInfo?.quickLoginAnonymousPhone as string
      if (anonymousPhone && anonymousPhone.length > 0) {
        this.quickLoginAnonymousPhone = anonymousPhone
        console.info(`Huawei quick login available: ${anonymousPhone}`)
      }
      // Huawei account exists — show the button regardless of anonymous phone
      this.huaweiLoginAvailable = true
    } catch (error) {
      const err = error as BusinessError
      // Not logged in to Huawei or not supported — silently fall back to phone login
      console.info(`Huawei quick login not available: code=${err.code}`)
      this.huaweiLoginAvailable = false
    }
  }

  /**
   * Handle Huawei one-click login by sending authCode to the gateway.
   */
  private async handleHuaweiLogin(authCode: string, unionID: string, openID: string) {
    this.isLoading = true
    this.errorMessage = ''
    try {
      await this.authService.loginWithHuaweiAuthCode(authCode, unionID, openID)
      this.isLoading = false
      this.authService.completeAuth()
    } catch (err) {
      this.errorMessage = (err as Error).message || 'Huawei login failed'
      this.isLoading = false
    }
  }

  private handlePrimaryAction() {
    if (!this.codeSent) {
      this.sendCode()
    } else {
      this.verifyAndLogin()
    }
  }

  private sendCode() {
    if (this.phoneNumber.length !== 11 || this.isLoading) {
      if (this.phoneNumber.length !== 11) {
        this.errorMessage = 'Please enter an 11-digit phone number'
      }
      return
    }
    this.isLoading = true
    this.errorMessage = ''

    this.authService.sendVerificationCode(this.phoneNumber).then(() => {
      this.codeSent = true
      this.isLoading = false
      this.startCountdown()
    }).catch((err: Error) => {
      this.errorMessage = err.message || 'Failed to send verification code'
      this.isLoading = false
    })
  }

  private verifyAndLogin() {
    if (this.verifyCode.length < 6 || this.isLoading) {
      return
    }
    this.isLoading = true
    this.errorMessage = ''

    this.authService.login(this.phoneNumber, this.verifyCode).then(() => {
      this.isLoading = false
      this.authService.completeAuth()
    }).catch((err: Error) => {
      this.errorMessage = err.message || 'Verification failed'
      this.isLoading = false
    })
  }

  private startCountdown() {
    this.countdown = 60
    this.countdownTimer = setInterval(() => {
      this.countdown--
      if (this.countdown <= 0) {
        clearInterval(this.countdownTimer)
        this.countdownTimer = -1
      }
    }, 1000) as number
  }
}
