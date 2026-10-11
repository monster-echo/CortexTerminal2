import { ApiService, AuthService, AuthState, I18n, showI18nToast, AnalyticsService, lightHaptic, clickHaptic } from '@rwecho/core'
import { AvatarPicker } from '../service/AvatarPicker'

@Component
export struct ProfilePage {
  @StorageLink('language') currentLanguage: string = 'en'
  @State displayName: string = ''
  @State avatarDisplayUrl: string = ''
  @State editDisplayName: string = ''
  @State editError: string = ''
  @State isSaving: boolean = false
  @State isUploadingAvatar: boolean = false

  onSaved: () => void = () => {}

  async aboutToAppear() {
    AnalyticsService.onPageStart('settings/Page')
    await this.loadProfile()
    this.editDisplayName = this.displayName
  }

  /** 响应式 i18n：引用 currentLanguage 让 Text 订阅 language，切语言时自动刷新 */
  private tr(key: string): string {
    return I18n.get(key) + (this.currentLanguage ? '' : '')
  }

  build() {
    this.EditProfileSheet()
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
      } catch (e) { this.editError = (e as Error).message || I18n.get('common.error') }
    }
    this.avatarDisplayUrl = AuthState.getResolvedAvatarUrl()
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
      this.onSaved()
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
        Text(this.tr('security.edit_profile'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_text'))
          .width('100%')
          .margin({ bottom: 16 })

        // Avatar (tap to pick from album)
        Column() {
          if (this.isUploadingAvatar) {
            LoadingProgress().width(40).height(40).color($r('app.color.terminal_text_muted'))
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

        Text(this.tr('security.change_avatar'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_primary_container'))
          .margin({ top: 8, bottom: 20 })

        Text(this.tr('security.display_name'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_text_muted'))
          .width('100%')
          .margin({ bottom: 6 })

        TextInput({ text: this.editDisplayName, placeholder: this.tr('security.display_name') })
          .width('100%')
          .height(44)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_background_element'))
          .fontColor($r('app.color.terminal_text'))
          .placeholderColor($r('app.color.terminal_text_muted'))
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
            LoadingProgress().width(20).height(20).color($r('app.color.terminal_inverse_on_surface'))
          } else {
            Text(this.tr('common.save'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_inverse_on_surface'))
          }
        }
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor($r('app.color.terminal_inverse_surface'))
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
    .backgroundColor($r('app.color.terminal_background'))
  }
}
