/**
 * @file LoginPage.ets
 * @brief Login page with official Huawei one-click login (2-step) and username/password login.
 *
 * Step 1: createAuthorizationWithHuaweiIDRequest → anonymous phone
 * Step 2: LoginWithHuaweiIDButton → Authorization Code
 */
import { AuthService, I18n, RouteName, showToast, AnalyticsService, lightHaptic, clickHaptic } from '@rwecho/core'
import { authentication, loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { resourceManager } from '@kit.LocalizationKit'

const TERMS_TAG = 'terms'
const PRIVACY_TAG = 'privacy'
const HUAWEI_AUTH_TAG = 'huawei_auth'

@Component
export struct LoginPage {
  @State loginMode: string = 'huawei'
  @State isHuaweiLoading: boolean = false
  @State isPasswordLoading: boolean = false
  @State errorMessage: string = ''
  @State username: string = ''
  @State password: string = ''
  @State anonymousPhone: string = ''
  @State isAgreementAccepted: boolean = false
  @StorageLink('language') currentLang: string = 'en'
  @Consume('pageStack') pageStack: NavPathStack
  privacyText: loginComponentManager.PrivacyText[] = [
    { text: I18n.get('auth.login.agree_read'), type: loginComponentManager.TextType.PLAIN_TEXT } as loginComponentManager.PrivacyText,
    { text: '《' + I18n.get('auth.login.terms') + '》', tag: TERMS_TAG, type: loginComponentManager.TextType.RICH_TEXT } as loginComponentManager.PrivacyText,
    { text: '《' + I18n.get('auth.login.privacy') + '》', tag: PRIVACY_TAG, type: loginComponentManager.TextType.RICH_TEXT } as loginComponentManager.PrivacyText,
    { text: I18n.get('auth.login.agree_and'), type: loginComponentManager.TextType.PLAIN_TEXT } as loginComponentManager.PrivacyText,
    { text: '《' + I18n.get('auth.login.huawei_agreement') + '》', tag: HUAWEI_AUTH_TAG, type: loginComponentManager.TextType.RICH_TEXT } as loginComponentManager.PrivacyText,
    { text: '。', type: loginComponentManager.TextType.PLAIN_TEXT } as loginComponentManager.PrivacyText,
  ]

  private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError | undefined,
         response: loginComponentManager.HuaweiIDCredential) => {
          if (error) {
            console.warn(`[HuaweiLogin] SDK error: code=${error.code} msg=${error.message}`)
            if (error.code === 1005300001) {
              this.agreementDialogController.open()
              return
            }
            if (error.code !== 1001502012 && error.code !== 1001502001) {
              this.errorMessage = I18n.get('auth.login.huawei_failed') + ` (${error.code})`
            }
            return
          }
          if (!this.isAgreementAccepted) {
            this.agreementDialogController.open()
            return
          }
          if (response) {
            const authCode = response.authorizationCode ?? ''
            const unionID = response.unionID ?? ''
            const openID = response.openID ?? ''
            console.info(`[HuaweiLogin] authCode=${authCode.substring(0, 20)}... unionID=${unionID} openID=${openID}`)
            if (authCode.length === 0) {
              this.errorMessage = I18n.get('auth.login.no_auth_code')
              return
            }
            this.handleHuaweiLogin(authCode, unionID, openID)
          }
        }
      )

  private agreementDialogController: CustomDialogController = new CustomDialogController({
    builder: AgreementDialog({
      privacyText: this.privacyText,
      cancel: () => {
        this.agreementDialogController.close()
      },
      confirm: () => {
        this.agreementDialogController.close()
        this.isAgreementAccepted = true
        this.huaweiButtonController.setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
        this.huaweiButtonController.continueLogin((error: BusinessError) => {
          if (error) {
            console.warn(`[HuaweiLogin] continueLogin error: code=${error.code} msg=${error.message}`)
          }
        })
      },
      clickHyperlinkText: (tag: string) => {
        this.agreementDialogController.close()
        this.handlePrivacyTagClick(tag)
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    backgroundColor: $r('app.color.terminal_surface_container'),
    cornerRadius: 16
  })

  aboutToAppear() {
    AnalyticsService.onPageStart('auth/Login')
    this.getAnonymousPhone()
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          this.BrandSection()

          if (this.loginMode === 'huawei') {
            this.HuaweiLoginSection()
            this.DividerSection()
            this.PasswordLoginEntry()
          } else {
            this.PasswordFormSection()
            this.DividerSection()
            this.HuaweiLoginEntry()
          }

          if (this.loginMode === 'huawei' && this.errorMessage.length > 0) {
            this.ErrorBanner()
          }
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      this.AgreementSection()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  // ── Brand Area ──────────────────────────────────────────────────

  @Builder
  BrandSection() {
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
    .margin({ top: 60 })
  }

  // ── Huawei One-Click Login ──────────────────────────────────────

  @Builder
  HuaweiLoginSection() {
    Column() {
      if (this.anonymousPhone.length > 0) {
        Text(this.anonymousPhone)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .textAlign(TextAlign.Center)
          .margin({ bottom: 8 })
      }

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
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
    .margin({ top: 48 })
  }

  // ── Agreement Checkbox ──────────────────────────────────────────

  @Builder
  AgreementSection() {
    Row() {
      Checkbox()
        .width(20)
        .height(20)
        .select(this.isAgreementAccepted)
        .onChange((value: boolean) => {
          clickHaptic()
          this.isAgreementAccepted = value
          if (value) {
            this.huaweiButtonController.setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
          } else {
            this.huaweiButtonController.setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
          }
        })
        .margin({ right: 8 })

      Text() {
        ForEach(this.privacyText, (item: loginComponentManager.PrivacyText, index?: number) => {
          if (item.type === loginComponentManager.TextType.PLAIN_TEXT) {
            Span(item.text)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .fontSize(12)
          } else {
            Span(item.text)
              .fontColor($r('app.color.terminal_secondary'))
              .fontSize(12)
              .onClick(() => {
                lightHaptic()
                this.handlePrivacyTagClick(item.tag ?? '')
              })
          }
        }, (item: loginComponentManager.PrivacyText, index?: number) => `${index}`)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 24, right: 24 })
    .margin({ top: 16 })
  }

  // ── Divider ─────────────────────────────────────────────────────

  @Builder
  DividerSection() {
    Row() {
      Divider()
        .layoutWeight(1)
        .color($r('app.color.terminal_outline_variant'))
      Text(I18n.get('auth.login.other_methods'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ left: 16, right: 16 })
      Divider()
        .layoutWeight(1)
        .color($r('app.color.terminal_outline_variant'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 24 })
    .padding({ left: 24, right: 24 })
  }

  // ── Password Login Entry Button (from huawei mode) ──────────────

  @Builder
  PasswordLoginEntry() {
    Column() {
      Button(I18n.get('auth.login.username_password_button'))
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: $r('app.color.terminal_outline_variant') })
        .fontColor($r('app.color.terminal_primary'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          clickHaptic()
          this.loginMode = 'password'
          this.errorMessage = ''
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 24, right: 24 })
    .margin({ top: 24 })
  }

  // ── Huawei Login Entry Button (from password mode) ──────────────

  @Builder
  HuaweiLoginEntry() {
    Column() {
      Button(I18n.get('auth.login.huawei_login_button'))
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: $r('app.color.terminal_outline_variant') })
        .fontColor($r('app.color.terminal_primary'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          clickHaptic()
          this.loginMode = 'huawei'
          this.errorMessage = ''
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 24, right: 24 })
    .margin({ top: 24 })
  }

  // ── Password Form (inline) ──────────────────────────────────────

  @Builder
  PasswordFormSection() {
    Column() {
      Text(I18n.get('auth.login.username_placeholder'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .width('100%')
        .margin({ bottom: 8 })

      TextInput({ placeholder: I18n.get('auth.login.enter_username'), text: this.username })
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

      Text(I18n.get('auth.login.password_placeholder'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })

      TextInput({ placeholder: I18n.get('auth.login.enter_password'), text: this.password })
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

      Button() {
        if (this.isPasswordLoading) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.terminal_on_secondary_container'))
        } else {
          Text(I18n.get('auth.login.button'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_on_secondary_container'))
        }
      }
      .width('100%')
      .height(48)
      .borderRadius(24)
      .backgroundColor($r('app.color.terminal_secondary_container'))
      .margin({ top: 20 })
      .enabled(this.username.length > 0 && this.password.length > 0 && !this.isPasswordLoading)
      .opacity(this.username.length > 0 && this.password.length > 0 ? 1 : 0.5)
      .onClick(() => {
        clickHaptic()
        this.handlePasswordLogin()
      })
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .margin({ top: 36 })
  }

  // ── Error Banner ────────────────────────────────────────────────

  @Builder
  ErrorBanner() {
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

  // ── Handlers ────────────────────────────────────────────────────

  private handlePrivacyTagClick(tag: string) {
    if (tag === TERMS_TAG) {
      const url = (this.getUIContext()?.getHostContext() as common.UIAbilityContext)
        .resourceManager.getStringByNameSync('terms_of_service_url')
      this.openExternal(url)
    } else if (tag === PRIVACY_TAG) {
      const url = (this.getUIContext()?.getHostContext() as common.UIAbilityContext)
        .resourceManager.getStringByNameSync('privacy_policy_url')
      this.openExternal(url)
    } else if (tag === HUAWEI_AUTH_TAG) {
      this.openExternal(this.getHuaweiAuthTermsUrl())
    }
  }

  private getHuaweiAuthTermsUrl(): string {
    const baseUrl = 'https://privacy.consumer.huawei.com/legal/id/authentication-terms.htm?code=CN&language=zh-CN'
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const colorMode = context.resourceManager.getConfigurationSync().colorMode
      if (colorMode === resourceManager.ColorMode.DARK) {
        return baseUrl + '&bgmode=black'
      }
    } catch (e) {
      // default to light mode URL
    }
    return baseUrl
  }

  private getAnonymousPhone() {
    const authRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest()
    authRequest.scopes = ['quickLoginAnonymousPhone']
    authRequest.state = util.generateRandomUUID()
    authRequest.forceAuthorization = false
    const controller = new authentication.AuthenticationController()
    controller.executeRequest(authRequest).then((response: authentication.AuthorizationWithHuaweiIDResponse) => {
      const phone: string = response.data?.extraInfo?.quickLoginAnonymousPhone as string ?? ''
      if (phone.length > 0) {
        console.info(`[HuaweiLogin] Got anonymous phone: ${phone}`)
        this.anonymousPhone = phone
      }
    }).catch((error: BusinessError) => {
      console.warn(`[HuaweiLogin] getAnonymousPhone error: code=${error.code} msg=${error.message}`)
    })
  }

  private async handleHuaweiLogin(authCode: string, unionID: string, openID: string) {
    this.isHuaweiLoading = true
    this.errorMessage = ''
    try {
      await AuthService.loginWithHuaweiAuthCode(authCode, unionID, openID)
      this.isHuaweiLoading = false
      AuthService.navigateHome(this.pageStack)
    } catch (err) {
      console.warn(`[HuaweiLogin] Backend error: ${(err as Error).message}`)
      this.errorMessage = (err as Error).message || I18n.get('auth.login.huawei_failed')
      this.isHuaweiLoading = false
    }
  }

  private async handlePasswordLogin() {
    if (!this.isAgreementAccepted) {
      this.agreementDialogController.open()
      return
    }
    if (this.username.length === 0 || this.password.length === 0) {
      this.errorMessage = I18n.get('auth.login.enter_credentials')
      return
    }

    this.isPasswordLoading = true
    this.errorMessage = ''
    try {
      await AuthService.loginWithPassword(this.username, this.password)
      this.isPasswordLoading = false
      AuthService.navigateHome(this.pageStack)
    } catch (err) {
      this.errorMessage = (err as Error).message || I18n.get('auth.login.error')
      this.isPasswordLoading = false
    }
  }

  private openExternal(url: string) {
    const navParam: Record<string, string> = { 'url': url }
    this.pageStack.pushPath({ name: RouteName.WEB_PAGE, param: navParam })
  }
}

@CustomDialog
struct AgreementDialog {
  controller: CustomDialogController
  privacyText: loginComponentManager.PrivacyText[] = []
  cancel: () => void = () => {}
  confirm: () => void = () => {}
  clickHyperlinkText: (tag: string) => void = () => {}

  build() {
    Column() {
      Text(I18n.get('auth.login.agreement_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 24, bottom: 16 })

      Text() {
        ForEach(this.privacyText, (item: loginComponentManager.PrivacyText, index?: number) => {
          if (item.type === loginComponentManager.TextType.PLAIN_TEXT) {
            Span(item.text)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .fontSize(14)
          } else {
            Span(item.text)
              .fontColor($r('app.color.terminal_secondary'))
              .fontSize(14)
              .onClick(() => {
                this.clickHyperlinkText(item.tag ?? '')
              })
          }
        }, (item: loginComponentManager.PrivacyText, index?: number) => `${index}`)
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .margin({ bottom: 24 })

      Row() {
        Button(I18n.get('auth.login.agreement_cancel'))
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.terminal_primary'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            this.cancel()
          })

        Button(I18n.get('auth.login.agreement_confirm'))
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            this.confirm()
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 24 })
    }
    .backgroundColor($r('app.color.terminal_surface_container'))
    .borderRadius(16)
  }
}
