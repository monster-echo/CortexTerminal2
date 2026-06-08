import { common, Want } from '@kit.AbilityKit'
import { ApiService, AuthService, AuthState, I18n, RouteName } from '@rwecho/core'

@Component
export struct SettingsPage {
  @State currentTheme: string = 'system'
  @StorageLink('language') currentLanguage: string = 'en'
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @State editedGatewayUrl: string = ''
  @State showGatewayEditor: boolean = false
  @State displayName: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  private appVersion: string = '1.0.0'
  private appBuild: string = '1'

  aboutToAppear() {
    this.editedGatewayUrl = this.gatewayUrl
    this.loadProfile()
  }

  build() {
    Scroll() {
      Column() {
        this.SectionHeader(I18n.get('settings.appearance'))

        Row() {
          Text(I18n.get('settings.theme'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.ThemeOption(I18n.get('settings.theme_light'), this.currentTheme === 'light', 'light')
            this.ThemeOption(I18n.get('settings.theme_dark'), this.currentTheme === 'dark', 'dark')
            this.ThemeOption(I18n.get('settings.theme_system'), this.currentTheme === 'system', 'system')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        Row() {
          Text(I18n.get('settings.language'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.LanguageOption(I18n.get('settings.language_zh'), 'zh')
            this.LanguageOption(I18n.get('settings.language_en'), 'en')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        this.SectionHeader(I18n.get('settings.connection'))

        Column() {
          Row() {
            Text(I18n.get('settings.gateway_url'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_primary'))
              .layoutWeight(1)

            Text(this.showGatewayEditor ? I18n.get('common.done') : I18n.get('settings.gateway_url'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_secondary'))
              .onClick(() => {
                if (this.showGatewayEditor) {
                  this.gatewayUrl = this.editedGatewayUrl
                }
                this.showGatewayEditor = !this.showGatewayEditor
              })
          }
          .width('100%')

          Text(this.gatewayUrl)
            .fontSize(13)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 4 })

          if (this.showGatewayEditor) {
            TextInput({ text: this.editedGatewayUrl, placeholder: 'https://...' })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_surface_container'))
              .fontColor($r('app.color.terminal_primary'))
              .margin({ top: 8 })
              .onChange((value: string) => {
                this.editedGatewayUrl = value
              })
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        this.SectionHeader(I18n.get('settings.account'))

        Row() {
          Column() {
            Text(this.displayName || I18n.get('settings.profile'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_primary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        this.NavRow(I18n.get('settings.account_security'), () => {
          this.pageStack.pushPath({ name: RouteName.ACCOUNT_SECURITY })
        })

        this.NavRow(I18n.get('settings.activate_worker'), () => {
          this.pageStack.pushPath({ name: RouteName.ACTIVATE_WORKER })
        })

        Button(I18n.get('settings.logout'))
          .width('calc(100% - 40vp)')
          .height(48)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_error'))
          .fontColor(Color.White)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 8 })
          .onClick(() => {
            this.confirmLogout()
          })

        this.SectionHeader(I18n.get('settings.about'))

        this.LinkRow(I18n.get('settings.terms'), this.gatewayUrl + '/terms', () => {
          this.openExternal(this.gatewayUrl + '/terms')
        })

        this.LinkRow(I18n.get('settings.privacy'), this.gatewayUrl + '/privacy', () => {
          this.openExternal(this.gatewayUrl + '/privacy')
        })

        this.LinkRow(I18n.get('settings.huawei_agreement'), 'consumer.huawei.com', () => {
          this.openExternal('https://consumer.huawei.com/minisite/cloudservice/hiapp/terms.htm')
        })

        Column() {
          Row() {
            Text(I18n.get('settings.version'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_primary'))
              .layoutWeight(1)

            Text(`${this.appVersion} (${this.appBuild})`)
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
          }
          .width('100%')

          Row() {
            Text($r('app.string.app_name'))
              .fontSize(12)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .layoutWeight(1)

            Text('HarmonyOS NEXT')
              .fontSize(12)
              .fontColor($r('app.color.terminal_on_surface_variant'))
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        Blank().height(40)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  SectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.terminal_secondary'))
      .textCase(TextCase.UpperCase)
      .width('calc(100% - 40vp)')
      .margin({ top: 20, bottom: 8 })
  }

  @Builder
  ThemeOption(label: string, selected: boolean, value: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(selected ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_on_surface_variant'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(selected ?
        $r('app.color.terminal_secondary_container') :
        Color.Transparent)
      .onClick(() => {
        this.currentTheme = value
        this.applyTheme(this.currentTheme)
      })
  }

  @Builder
  LanguageOption(label: string, code: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.currentLanguage === code ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.currentLanguage === code ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_on_surface_variant'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(this.currentLanguage === code ?
        $r('app.color.terminal_secondary_container') :
        Color.Transparent)
      .onClick(() => {
        this.currentLanguage = code
        AppStorage.setOrCreate('language', code)
      })
  }

  @Builder
  NavRow(title: string, action: () => void) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor($r('app.color.terminal_primary'))
        .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.terminal_on_surface_variant')])
    }
    .width('calc(100% - 40vp)')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ bottom: 8 })
    .onClick(() => {
      action()
    })
  }

  @Builder
  LinkRow(title: string, value: string, action: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(14)
          .fontColor($r('app.color.terminal_primary'))

        Text(value)
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(I18n.get('common.confirm'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_secondary'))
    }
    .width('calc(100% - 40vp)')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ bottom: 8 })
    .onClick(() => {
      action()
    })
  }

  private applyTheme(theme: string) {
    AppStorage.setOrCreate('themeMode', theme)
  }

  private async loadProfile() {
    const name = AuthState.getDisplayName()
    if (name.length > 0) {
      this.displayName = name
      return
    }
    try {
      const profile = await ApiService.getProfile()
      const dn = (profile['displayName'] as string) ?? ''
      const un = (profile['username'] as string) ?? ''
      this.displayName = dn.length > 0 ? dn : un
    } catch (_e) {}
  }

  private confirmLogout() {
    AlertDialog.show({
      title: I18n.get('settings.logout_confirm_title'),
      message: I18n.get('settings.logout_confirm_message'),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('settings.logout'),
        action: () => {
          AuthService.logout()
          this.pageStack.replacePath({ name: RouteName.AUTH_LOGIN })
        }
      }
    })
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
