import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { ApiService, AuthService, AuthState, I18n, RouteName, AppConstants, showI18nToast, showToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic, heavyHaptic } from '@rwecho/core'

@Component
export struct SettingsPage {
  @StorageLink('themeMode') currentTheme: string = 'system'
  @StorageLink('language') currentLanguage: string = 'en'
  @State displayName: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('appVersion') appVersion: string = '1.0.0'

  aboutToAppear() {
    AnalyticsService.onPageStart('settings/Page')
    this.loadProfile()
  }

  private get gatewayUrl(): string {
    return AppStorage.get<string>('gatewayUrl') || AppConstants.DEFAULT_GATEWAY_URL
  }

  build() {
    Scroll() {
      Column() {
        // Avatar + Username header
        Column() {
          Text(this.displayName.length > 0 ? this.displayName.substring(0, 1).toUpperCase() : 'U')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .width(56)
            .height(56)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .borderRadius(28)

          Text(this.displayName || (I18n.get('settings.profile') + (this.currentLanguage ? '' : '')))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16, bottom: 8 })

        this.SectionHeader('settings.appearance')

        Row() {
          Text(I18n.get('settings.theme') + (this.currentLanguage ? '' : ''))
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.ThemeOption('settings.theme_light', 'light')
            this.ThemeOption('settings.theme_dark', 'dark')
            this.ThemeOption('settings.theme_system', 'system')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        Row() {
          Text(I18n.get('settings.language') + (this.currentLanguage ? '' : ''))
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.LanguageOption('settings.language_zh', 'zh')
            this.LanguageOption('settings.language_en', 'en')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        this.SectionHeader('settings.account')

        this.NavRow('settings.account_security', () => {
          this.pageStack.pushPath({ name: RouteName.ACCOUNT_SECURITY })
        })

        this.NavRow('settings.activate_worker', () => {
          this.pageStack.pushPath({ name: RouteName.ACTIVATE_WORKER })
        })

        Button(I18n.get('settings.logout') + (this.currentLanguage ? '' : ''))
          .width('calc(100% - 40vp)')
          .height(48)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_error'))
          .fontColor(Color.White)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 8 })
          .onClick(() => {
            heavyHaptic()
            this.confirmLogout()
          })

        // Watermark footer
        Column() {
          Row() {
            Text(I18n.get('settings.footer_terms') + (this.currentLanguage ? '' : ''))
              .fontSize(13)
              .fontColor($r('app.color.terminal_secondary'))
              .onClick(() => {
                lightHaptic()
                this.openExternal(this.gatewayUrl + '/terms')
              })

            Text(' | ')
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))

            Text(I18n.get('settings.footer_privacy') + (this.currentLanguage ? '' : ''))
              .fontSize(13)
              .fontColor($r('app.color.terminal_secondary'))
              .onClick(() => {
                lightHaptic()
                this.openExternal(this.gatewayUrl + '/privacy')
              })
          }

          Text(`v${this.appVersion} · CortexTerminal`)
            .fontSize(11)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 32, bottom: 24 })

        Blank().height(40)
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  SectionHeader(key: string) {
    Text(I18n.get(key) + (this.currentLanguage ? '' : ''))
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.terminal_secondary'))
      .textCase(TextCase.UpperCase)
      .width('calc(100% - 40vp)')
      .margin({ top: 20, bottom: 8 })
  }

  @Builder
  ThemeOption(key: string, value: string) {
    Text(I18n.get(key) + (this.currentLanguage ? '' : ''))
      .fontSize(13)
      .fontWeight(this.currentTheme === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.currentTheme === value ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_on_surface_variant'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(this.currentTheme === value ?
        $r('app.color.terminal_secondary_container') :
        Color.Transparent)
      .onClick(() => {
        clickHaptic()
        this.currentTheme = value
        this.applyTheme(this.currentTheme)
        AnalyticsService.onEvent(AnalyticsEvent.THEME_CHANGE)
        showToast(I18n.get('settings.theme_changed').replace('{v}', I18n.get(`settings.theme_${value}`)))
      })
  }

  @Builder
  LanguageOption(key: string, code: string) {
    Text(I18n.get(key) + (this.currentLanguage ? '' : ''))
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
        clickHaptic()
        this.currentLanguage = code
        AnalyticsService.onEvent(AnalyticsEvent.LANGUAGE_CHANGE)
        showToast(I18n.get('settings.language_changed').replace('{v}', I18n.get(`settings.language_${code}`)))
      })
  }

  @Builder
  NavRow(key: string, action: () => void) {
    Row() {
      Text(I18n.get(key) + (this.currentLanguage ? '' : ''))
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
      lightHaptic()
      action()
    })
  }

  private applyTheme(theme: string) {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
    try {
      if (theme === 'system') {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      } else {
        const colorMode = theme === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        context.getApplicationContext().setColorMode(colorMode)
      }
    } catch (_e) {}
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
    this.getUIContext()?.showAlertDialog({
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
          showI18nToast('settings.logout_success')
        }
      }
    })
  }

  private openExternal(url: string) {
    const navParam: Record<string, string> = { 'url': url }
    this.pageStack.pushPath({ name: RouteName.WEB_PAGE, param: navParam })
  }
}
