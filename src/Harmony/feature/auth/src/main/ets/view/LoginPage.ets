/**
 * @file LoginPage.ets
 * @brief Login page with Huawei one-click login and username/password login via bindSheet.
 */
import { AuthService, I18n, AppConstants, showI18nToast } from '@rwecho/core'
import { loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common, Want } from '@kit.AbilityKit'

@Component
export struct LoginPage {
  @State showPasswordSheet: boolean = false
  @State isHuaweiLoading: boolean = false
  @State isPasswordLoading: boolean = false
  @State errorMessage: string = ''
  @State username: string = ''
  @State password: string = ''
  @StorageLink('language') currentLang: string = 'en'
  @Consume('pageStack') pageStack: NavPathStack

  private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError | undefined,
         response: loginComponentManager.HuaweiIDCredential) => {
          if (error) {
            if (error.code !== 1001502012 && error.code !== 1001502001) {
              this.errorMessage = I18n.get('auth.login.huawei_failed')
            }
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

  build() {
    Scroll() {
      Column() {
        this.BrandSection()
        this.HuaweiLoginSection()

        this.DividerSection()

        this.PasswordLoginEntry()

        if (this.errorMessage.length > 0) {
          this.ErrorBanner()
        }

        Blank()

        this.BottomSection()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
    .scrollBar(BarState.Off)
    .bindSheet($$this.showPasswordSheet, this.PasswordSheetContent(), {
      height: SheetSize.LARGE,
      showClose: true,
      backgroundColor: $r('app.color.terminal_surface'),
      onDisappear: () => { this.showPasswordSheet = false }
    })
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
    .margin({ top: 80 })
  }

  // ── Huawei One-Click Login ──────────────────────────────────────

  @Builder
  HuaweiLoginSection() {
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
  }

  // ── Password Login Entry Button ─────────────────────────────────

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
          this.showPasswordSheet = true
          this.errorMessage = ''
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 24, right: 24 })
    .margin({ top: 24 })
  }

  // ── Password Login Sheet ────────────────────────────────────────

  @Builder
  PasswordSheetContent() {
    Column() {
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
          this.handlePasswordLogin()
        })
      }
      .width('100%')
      .padding(20)
      .borderRadius(12)
      .backgroundColor($r('app.color.terminal_surface_container'))
      .margin({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 24 })
    .backgroundColor($r('app.color.terminal_surface'))
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
    .margin({ top: 16 })
  }

  // ── Bottom Section ──────────────────────────────────────────────

  @Builder
  BottomSection() {
    Column() {
      Text($r('app.string.login_tagline'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 8 })

      Text() {
        Span(I18n.get('auth.login.agree_prefix'))
          .fontColor($r('app.color.terminal_on_surface_variant'))
        Span(I18n.get('auth.login.terms'))
          .fontColor($r('app.color.terminal_secondary'))
          .onClick(() => {
            this.openExternal((AppStorage.get<string>('gatewayUrl') || AppConstants.DEFAULT_GATEWAY_URL) + '/terms')
          })
        Span(I18n.get('auth.login.agree_and'))
          .fontColor($r('app.color.terminal_on_surface_variant'))
        Span(I18n.get('auth.login.privacy'))
          .fontColor($r('app.color.terminal_secondary'))
          .onClick(() => {
            this.openExternal((AppStorage.get<string>('gatewayUrl') || AppConstants.DEFAULT_GATEWAY_URL) + '/privacy')
          })
      }
      .fontSize(12)
      .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ bottom: 24 })
  }

  // ── Handlers ────────────────────────────────────────────────────

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

  private async openExternal(url: string) {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const want = new Want()
      want.action = 'ohos.want.action.viewData'
      want.uri = url
      await context.startAbility(want)
    } catch (e) {
      showI18nToast('common.link_open_failed')
    }
  }
}
