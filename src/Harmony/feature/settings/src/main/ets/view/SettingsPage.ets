/**
 * @file SettingsPage.ets
 * @brief Settings page with theme, language, and version info
 *
 * Provides user-configurable settings including dark/light theme toggle,
 * language selection, gateway URL configuration, and app version display.
 */
import { Configuration, ConfigurationConstant } from '@kit.AbilityKit'

@Component
export struct SettingsPage {
  @State currentTheme: string = 'system'
  @State currentLanguage: string = 'en'
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''
  @State editedGatewayUrl: string = ''
  @State showGatewayEditor: boolean = false
  private appVersion: string = '1.0.0'
  private appBuild: string = '1'

  aboutToAppear() {
    this.editedGatewayUrl = this.gatewayUrl
  }

  build() {
    Scroll() {
      Column() {
        // Header
        Text('Settings')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .width('100%')
          .padding({ left: 20, top: 16, bottom: 16 })

        // Appearance section
        this.SectionHeader('Appearance')

        // Theme selector
        Row() {
          Text('Theme')
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.ThemeOption('Light', this.currentTheme === 'light')
            this.ThemeOption('Dark', this.currentTheme === 'dark')
            this.ThemeOption('System', this.currentTheme === 'system')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        // Language selector
        Row() {
          Text('Language')
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.LanguageOption('English', 'en')
            this.LanguageOption('Chinese', 'zh')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        // Connection section
        this.SectionHeader('Connection')

        // Gateway URL
        Column() {
          Row() {
            Text('Gateway URL')
              .fontSize(14)
              .fontColor($r('app.color.terminal_primary'))
              .layoutWeight(1)

            Text(this.showGatewayEditor ? 'Done' : 'Edit')
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

          Text(this.gatewayUrl || 'https://gateway.ct.rwecho.top')
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

        // Account section
        this.SectionHeader('Account')

        // Logout button
        Button('Sign Out')
          .width('calc(100% - 40vp)')
          .height(48)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_error'))
          .fontColor(Color.White)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 8 })
          .onClick(() => {
            this.authToken = ''
            AppStorage.setOrCreate('isLoggedIn', false)
          })

        // About section
        this.SectionHeader('About')

        // Version info
        Column() {
          Row() {
            Text('Version')
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
  ThemeOption(label: string, selected: boolean) {
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
        this.currentTheme = label.toLowerCase()
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

  private applyTheme(theme: string) {
    AppStorage.setOrCreate('themeMode', theme)
    // The EntryAbility will pick up the change via Configuration
  }
}
