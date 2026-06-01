/**
 * @file SettingsPage.ets
 * @brief Settings page with theme, language, and version info
 *
 * Provides user-configurable settings including dark/light theme toggle,
 * language selection, gateway URL configuration, and app version display.
 */
import { common, Want } from '@kit.AbilityKit'
import { RestApiClient } from '@rwecho/terminal'

@Component
export struct SettingsPage {
  @State currentTheme: string = 'system'
  @StorageLink('language') currentLanguage: string = 'en'
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''
  @StorageLink('userInfo') userInfoStr: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @State editedGatewayUrl: string = ''
  @State showGatewayEditor: boolean = false
  @State displayName: string = ''
  private appVersion: string = '1.0.0'
  private appBuild: string = '1'
  private apiClient: RestApiClient = new RestApiClient()

  aboutToAppear() {
    this.editedGatewayUrl = this.gatewayUrl
    this.loadProfile()
  }

  build() {
    Scroll() {
      Column() {
        // Appearance section
        this.SectionHeader('外观')

        // Theme selector
        Row() {
          Text('主题')
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.ThemeOption('浅色', this.currentTheme === 'light', 'light')
            this.ThemeOption('深色', this.currentTheme === 'dark', 'dark')
            this.ThemeOption('系统', this.currentTheme === 'system', 'system')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        // Language selector
        Row() {
          Text('语言')
            .fontSize(14)
            .fontColor($r('app.color.terminal_primary'))
            .layoutWeight(1)

          Row() {
            this.LanguageOption('中文', 'zh')
            this.LanguageOption('English', 'en')
          }
        }
        .width('calc(100% - 40vp)')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })

        // Connection section
        this.SectionHeader('连接')

        // Gateway URL
        Column() {
          Row() {
            Text('网关地址')
              .fontSize(14)
              .fontColor($r('app.color.terminal_primary'))
              .layoutWeight(1)

            Text(this.showGatewayEditor ? '完成' : '编辑')
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

        // Account section
        this.SectionHeader('账号')

        // User profile
        Row() {
          Column() {
            Text(this.displayName || '已登录用户')
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

        // Account security
        this.NavRow('账号安全', () => {
          this.pageStack.pushPath({ name: 'AccountSecurity' })
        })

        // Activate worker
        this.NavRow('激活 Worker', () => {
          this.pageStack.pushPathByName('Auth', undefined)
        })

        // Logout button
        Button('退出登录')
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

        // About section
        this.SectionHeader('关于')

        this.LinkRow('用户协议', this.gatewayUrl + '/terms', () => {
          this.openExternal(this.gatewayUrl + '/terms')
        })

        this.LinkRow('隐私协议', this.gatewayUrl + '/privacy', () => {
          this.openExternal(this.gatewayUrl + '/privacy')
        })

        this.LinkRow('华为账号用户认证协议', 'consumer.huawei.com', () => {
          this.openExternal('https://consumer.huawei.com/minisite/cloudservice/hiapp/terms.htm')
        })

        // Version info
        Column() {
          Row() {
            Text('版本')
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

      Text('打开')
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
    // The EntryAbility will pick up the change via Configuration
  }

  private async loadProfile() {
    // Load display name from stored user info or from API
    if (this.userInfoStr.length > 0) {
      try {
        const user = JSON.parse(this.userInfoStr) as Record<string, string>
        this.displayName = user['displayName'] || user['username'] || ''
      } catch (_e) {}
    }
    if (this.displayName.length === 0) {
      try {
        const profile: Record<string, Object> = await this.apiClient.getProfile()
        const dn: string = (profile['displayName'] as string) ?? ''
        const un: string = (profile['username'] as string) ?? ''
        this.displayName = dn.length > 0 ? dn : un
        if (this.displayName.length > 0) {
          AppStorage.setOrCreate('userInfo', JSON.stringify(profile))
        }
      } catch (_e) {}
    }
  }

  private confirmLogout() {
    AlertDialog.show({
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '退出登录',
        action: () => {
          this.logout()
        }
      }
    })
  }

  private logout() {
    this.authToken = ''
    AppStorage.setOrCreate('isLoggedIn', false)
    AppStorage.setOrCreate('authCompleted', false)
    AppStorage.setOrCreate('userInfo', '')
    AppStorage.setOrCreate('refreshToken', '')
    this.pageStack.replacePath({ name: 'Auth' })
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
