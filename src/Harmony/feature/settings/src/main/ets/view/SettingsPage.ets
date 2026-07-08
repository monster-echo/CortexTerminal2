import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { ApiService, AuthService, AuthState, I18n, RouteName, showI18nToast, showToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic, heavyHaptic } from '@rwecho/core'
import { AvatarPicker } from '../service/AvatarPicker'

@Component
export struct SettingsPage {
  @StorageLink('themeMode') currentTheme: string = 'system'
  @StorageLink('language') currentLanguage: string = 'en'
  @State displayName: string = ''
  @State avatarDisplayUrl: string = ''
  @State showEditProfile: boolean = false
  @State editDisplayName: string = ''
  @State editError: string = ''
  @State isSaving: boolean = false
  @State isUploadingAvatar: boolean = false
  @State devTapCount: number = 0
  @State showDevOptions: boolean = false
  @StorageLink('webglEnabled') webglEnabled: boolean = true
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('appVersion') appVersion: string = '1.0.0'

  aboutToAppear() {
    AnalyticsService.onPageStart('settings/Page')
    this.loadProfile()
    this.showDevOptions = AppStorage.get<boolean>('showDevOptions') ?? false
  }

  build() {
    Scroll() {
      Column() {
        // Avatar + Username header (tap to edit profile)
        Column() {
          if (this.avatarDisplayUrl.length > 0) {
            Image(this.avatarDisplayUrl)
              .width(56)
              .height(56)
              .borderRadius(28)
          } else {
            Text(this.displayName.length > 0 ? this.displayName.substring(0, 1).toUpperCase() : 'U')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .width(56)
              .height(56)
              .textAlign(TextAlign.Center)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .borderRadius(28)
          }

          Text(this.displayName || (I18n.get('settings.profile') + (this.currentLanguage ? '' : '')))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16, bottom: 8 })
        .onClick(() => {
          lightHaptic()
          this.openEditProfile()
        })

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

        if (this.showDevOptions) {
          this.SectionHeader('Developer Options')

          Row() {
            Text('GPU Acceleration (WebGL)')
              .fontSize(14)
              .fontColor($r('app.color.terminal_primary'))
              .layoutWeight(1)

            Checkbox()
              .width(20)
              .height(20)
              .select(this.webglEnabled)
              .onChange((value: boolean) => {
                this.webglEnabled = value
                AppStorage.setOrCreate('webglEnabled', value)
              })
          }
          .width('calc(100% - 40vp)')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ bottom: 8 })
        }

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

        this.SectionHeader('settings.support')

        this.NavRow('settings.contact_support', () => {
          this.pageStack.pushPath({ name: RouteName.CONTACT_SUPPORT })
        })

        this.NavRow('settings.feedback', () => {
          const param: Record<string, string> = { 'type': 'feedback' }
          this.pageStack.pushPath({ name: RouteName.FEEDBACK, param: param })
        })

        this.NavRow('settings.report', () => {
          const param: Record<string, string> = { 'type': 'report' }
          this.pageStack.pushPath({ name: RouteName.FEEDBACK, param: param })
        })

        // Watermark footer
        Column() {
          Row() {
            Text(I18n.get('settings.footer_terms') + (this.currentLanguage ? '' : ''))
              .fontSize(13)
              .fontColor($r('app.color.terminal_secondary'))
              .onClick(() => {
                lightHaptic()
                const url = (this.getUIContext()?.getHostContext() as common.UIAbilityContext)
                  .resourceManager.getStringByNameSync('terms_of_service_url')
                this.openExternal(url)
              })

            Text(' | ')
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))

            Text(I18n.get('settings.footer_privacy') + (this.currentLanguage ? '' : ''))
              .fontSize(13)
              .fontColor($r('app.color.terminal_secondary'))
              .onClick(() => {
                lightHaptic()
                const url = (this.getUIContext()?.getHostContext() as common.UIAbilityContext)
                  .resourceManager.getStringByNameSync('privacy_policy_url')
                this.openExternal(url)
              })
          }

          Text(`v${this.appVersion} · CortexTerminal`)
            .fontSize(11)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 6 })
            .onClick(() => {
              this.handleDevTap()
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 32, bottom: 24 })

        Blank().height(40)
      }
      .width('100%')
      .bindSheet(this.showEditProfile, this.EditProfileSheet(), {
        height: SheetSize.FIT_CONTENT,
        showClose: true,
        backgroundColor: $r('app.color.terminal_surface'),
        onDisappear: () => { this.showEditProfile = false }
      })
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
    this.displayName = AuthState.getDisplayName()
    // Login response only carries username; fetch profile once to pick up avatarUrl.
    if (AuthState.getAvatarUrl().length === 0) {
      try {
        const profile = await ApiService.getProfile()
        if (this.displayName.length === 0) {
          const dn = (profile['displayName'] as string) ?? ''
          const un = (profile['username'] as string) ?? ''
          this.displayName = dn.length > 0 ? dn : un
          AuthState.updateDisplayName(this.displayName)
        }
        const av = (profile['avatarUrl'] as string) ?? ''
        if (av.length > 0) {
          AuthState.updateAvatar(av)
        }
      } catch (_e) {}
    }
    this.avatarDisplayUrl = AuthState.getResolvedAvatarUrl()
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

  private openEditProfile() {
    this.editDisplayName = this.displayName
    this.editError = ''
    this.showEditProfile = true
  }

  private async submitEditProfile() {
    const name = this.editDisplayName.trim()
    if (name.length === 0) {
      this.editError = I18n.get('security.display_name_required')
      return
    }
    this.isSaving = true
    this.editError = ''
    try {
      await AuthService.updateDisplayName(name)
      this.displayName = name
      this.showEditProfile = false
      showI18nToast('security.display_name_changed')
    } catch (e) {
      this.editError = (e as Error).message || I18n.get('common.error')
    } finally {
      this.isSaving = false
    }
  }

  private async pickAvatar() {
    this.editError = ''
    try {
      const uri = await AvatarPicker.pickSingle()
      if (uri.length === 0) {
        return
      }
      const base64 = await AvatarPicker.readAsBase64(getContext(this), uri)
      if (base64.length === 0) {
        this.editError = I18n.get('security.avatar_too_large')
        return
      }
      this.isUploadingAvatar = true
      await AuthService.uploadAvatar(base64)
      this.avatarDisplayUrl = AuthState.getResolvedAvatarUrl()
      showI18nToast('security.avatar_changed')
    } catch (e) {
      console.error(`[SettingsPage] pickAvatar failed: ${(e as Error).message}`)
      this.editError = (e as Error).message || I18n.get('common.error')
    } finally {
      this.isUploadingAvatar = false
    }
  }

  @Builder
  EditProfileSheet() {
    Column() {
      Column() {
        Text(I18n.get('security.edit_profile'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .width('100%')
          .margin({ bottom: 16 })

        // Avatar (tap to pick from album)
        Column() {
          if (this.isUploadingAvatar) {
            LoadingProgress().width(40).height(40).color($r('app.color.terminal_on_surface_variant'))
          } else if (this.avatarDisplayUrl.length > 0) {
            Image(this.avatarDisplayUrl).width(72).height(72).borderRadius(36)
          } else {
            Text(this.displayName.length > 0 ? this.displayName.substring(0, 1).toUpperCase() : 'U')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .textAlign(TextAlign.Center)
          }
        }
        .width(72)
        .height(72)
        .borderRadius(36)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          lightHaptic()
          this.pickAvatar()
        })

        Text(I18n.get('security.change_avatar'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_secondary'))
          .margin({ top: 8, bottom: 20 })

        Text(I18n.get('security.display_name'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ bottom: 6 })

        TextInput({ text: this.editDisplayName, placeholder: I18n.get('security.display_name') })
          .width('100%')
          .height(44)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .fontColor($r('app.color.terminal_primary'))
          .placeholderColor($r('app.color.terminal_on_surface_variant'))
          .onChange((value: string) => {
            this.editDisplayName = value
          })

        if (this.editError.length > 0) {
          Text(this.editError)
            .fontSize(13)
            .fontColor($r('app.color.terminal_error'))
            .width('100%')
            .margin({ top: 8 })
        }

        Button() {
          if (this.isSaving) {
            LoadingProgress().width(20).height(20).color(Color.White)
          } else {
            Text(I18n.get('common.save'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_on_secondary_container'))
          }
        }
        .width('100%')
        .height(48)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .margin({ top: 20 })
        .enabled(!this.isSaving)
        .onClick(() => {
          clickHaptic()
          this.submitEditProfile()
        })
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private handleDevTap() {
    this.devTapCount++
    if (this.devTapCount >= 7) {
      this.devTapCount = 0
      this.showDevOptions = !this.showDevOptions
      AppStorage.setOrCreate('showDevOptions', this.showDevOptions)
      const msg = this.showDevOptions ? 'Developer options enabled' : 'Developer options disabled'
      showToast(msg + (this.currentLanguage ? '' : ''))
    }
    // Reset counter after 3s of inactivity
    setTimeout(() => {
      if (this.devTapCount > 0 && this.devTapCount < 7) {
        this.devTapCount = 0
      }
    }, 3000)
  }

  private openExternal(url: string) {
    const navParam: Record<string, string> = { 'url': url }
    this.pageStack.pushPath({ name: RouteName.WEB_PAGE, param: navParam })
  }
}
