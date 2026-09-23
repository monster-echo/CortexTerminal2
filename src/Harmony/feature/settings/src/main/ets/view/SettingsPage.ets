import { ApiService, AuthService, AuthState, I18n, RouteName, showI18nToast, showToast, AnalyticsService, lightHaptic, clickHaptic, heavyHaptic } from '@rwecho/core'
import { common } from '@kit.AbilityKit'
import { systemShare } from '@kit.ShareKit'
import { AvatarPicker } from '../service/AvatarPicker'
import { MarketLauncher } from '../service/MarketLauncher'

/** 导航行数据（图标 + i18n key + 点击动作），供分组卡片 ForEach 使用 */
class NavItem {
  icon: Resource | null = null
  labelKey: string = ''
  action: () => void = () => {}
}

/**
 * Settings 根页：用页面深度做减法 —— 根页只留导航入口（头像/账户/通用/支持/关于），
 * 细项全部下沉二级页（PreferencesPage / AboutPage），底部保留危险区与版本水印。
 */
@Component
export struct SettingsPage {
  @StorageLink('language') currentLanguage: string = 'en'
  @State displayName: string = ''
  @State avatarDisplayUrl: string = ''
  @State showEditProfile: boolean = false
  @State editDisplayName: string = ''
  @State editError: string = ''
  @State isSaving: boolean = false
  @State isUploadingAvatar: boolean = false
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('settings/Page')
    this.loadProfile()
  }

  /** 响应式 i18n：引用 currentLanguage 让 Text 订阅 language，切语言时自动刷新 */
  private tr(key: string): string {
    return I18n.get(key) + (this.currentLanguage ? '' : '')
  }

  private accountItems(): NavItem[] {
    const items: NavItem[] = []
    const redeem: NavItem = new NavItem()
    redeem.icon = $r('sys.symbol.gift')
    redeem.labelKey = 'settings.redeem_code_nav'
    redeem.action = (): void => {
      this.pageStack.pushPath({ name: RouteName.REDEEM })
    }
    items.push(redeem)
    return items
  }

  private securityItems(): NavItem[] {
    const items: NavItem[] = []
    const security: NavItem = new NavItem()
    security.icon = $r('sys.symbol.person_2')
    security.labelKey = 'settings.account_security'
    security.action = (): void => {
      this.pageStack.pushPath({ name: RouteName.ACCOUNT_SECURITY })
    }
    items.push(security)
    return items
  }

  private deviceItems(): NavItem[] {
    const items: NavItem[] = []
    const worker: NavItem = new NavItem()
    worker.icon = $r('sys.symbol.link')
    worker.labelKey = 'settings.activate_worker'
    worker.action = (): void => {
      this.pageStack.pushPath({ name: RouteName.ACTIVATE_WORKER })
    }
    items.push(worker)
    return items
  }

  private supportItems(): NavItem[] {
    const items: NavItem[] = []
    const support: NavItem = new NavItem()
    support.icon = $r('sys.symbol.envelope')
    support.labelKey = 'settings.contact_support'
    support.action = (): void => {
      this.pageStack.pushPath({ name: RouteName.CONTACT_SUPPORT })
    }
    items.push(support)
    const feedback: NavItem = new NavItem()
    feedback.icon = $r('sys.symbol.paperplane')
    feedback.labelKey = 'settings.feedback'
    feedback.action = (): void => {
      const param: Record<string, string> = { 'type': 'feedback' }
      this.pageStack.pushPath({ name: RouteName.FEEDBACK, param: param })
    }
    items.push(feedback)
    return items
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

          Text(this.displayName || this.tr('settings.profile'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_on_surface'))
            .margin({ top: 12 })

          Text(this.tr('settings.profile'))
            .fontSize(13)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 2 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16, bottom: 8 })
        .onClick(() => {
          lightHaptic()
          this.openEditProfile()
        })

        this.SectionHeader('settings.account')

        this.NavCard(this.accountItems())

        this.SectionHeader('settings.general')

        this.NavCard(this.generalItems())

        this.SectionHeader('settings.security_section')

        this.NavCard(this.securityItems())

        this.SectionHeader('settings.device_section')

        this.NavCard(this.deviceItems())

        this.SectionHeader('settings.support')

        this.NavCard(this.supportItems())

        this.SectionHeader('settings.about')

        this.NavCard(this.aboutItems())

        // 危险区：对齐 Flutter 端的分组行样式（error 色行，而非突兀的大红按钮）
        Blank().height(16)
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(20)
              .fontColor([$r('app.color.terminal_error')])

            Text(this.tr('settings.logout'))
              .fontSize(16)
              .fontColor($r('app.color.terminal_error'))
              .margin({ left: 12 })
              .layoutWeight(1)
          }
          .width('100%')
          .height(52)
          .onClick(() => {
            heavyHaptic()
            this.confirmLogout()
          })
        }
        .cardStyle()

        // Watermark footer
        Text(`v${this.appVersion()} · CortexTerminal`)
          .fontSize(11)
          .fontColor($r('app.color.terminal_text_tertiary'))
          .margin({ top: 32, bottom: 24 })

        Blank().height(40)
      }
      .width('100%')
      .bindSheet(this.showEditProfile, this.EditProfileSheet(), {
        height: SheetSize.MEDIUM,
        showClose: true,
        backgroundColor: $r('app.color.terminal_surface'),
        onDisappear: () => { this.showEditProfile = false }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_surface'))
    .align(Alignment.Top)
  }

  private generalItems(): NavItem[] {
    const items: NavItem[] = []
    const general: NavItem = new NavItem()
    general.icon = $r('sys.symbol.pencil_line_1')
    general.labelKey = 'settings.general'
    general.action = (): void => {
      this.pageStack.pushPath({ name: RouteName.PREFERENCES })
    }
    items.push(general)
    return items
  }

  private aboutItems(): NavItem[] {
    const items: NavItem[] = []
    const share: NavItem = new NavItem()
    share.icon = $r('sys.symbol.share')
    share.labelKey = 'settings.share_app'
    share.action = (): void => {
      this.shareApp()
    }
    items.push(share)
    const rate: NavItem = new NavItem()
    rate.icon = $r('sys.symbol.star')
    rate.labelKey = 'settings.rate_us'
    rate.action = (): void => {
      const context = getContext(this) as common.UIAbilityContext
      MarketLauncher.openAppDetail(context).catch((e: Error) => {
        showToast(I18n.getWithArgs('settings.rate_failed', { 'msg': e.message }))
      })
    }
    items.push(rate)
    const about: NavItem = new NavItem()
    about.icon = $r('sys.symbol.exclamationmark_circle')
    about.labelKey = 'settings.about'
    about.action = (): void => {
      this.pageStack.pushPath({ name: RouteName.ABOUT })
    }
    items.push(about)
    return items
  }

  /** 分享应用：系统分享面板带 AppGallery 详情链接（bundleName 与 AppScope/app.json5 一致） */
  private async shareApp() {
    const context = getContext(this) as common.UIAbilityContext
    const url = 'https://appgallery.huawei.com/app/detail?id=top.rwecho.cortexterminal'
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: 'general.text',
      content: I18n.getWithArgs('settings.share_app_text', { 'url': url })
    })
    const controller: systemShare.ShareController = new systemShare.ShareController(data)
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    })
  }

  private appVersion(): string {
    return AppStorage.get<string>('appVersion') ?? '1.0.0'
  }

  /** 分组导航卡片：圆角卡片容器 + 行间分割线（对齐 Flutter AppGroupCard） */
  @Builder
  NavCard(items: NavItem[]) {
    Column() {
      ForEach(items, (item: NavItem, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .color($r('app.color.terminal_outline_variant'))
              .margin({ left: 48 })
          }
          Row() {
            if (item.icon !== null) {
              SymbolGlyph(item.icon)
                .fontSize(20)
                .fontColor([$r('app.color.terminal_on_surface_variant')])
            }

            Text(this.tr(item.labelKey))
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface'))
              .margin({ left: item.icon !== null ? 12 : 0 })
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.terminal_text_tertiary')])
          }
          .width('100%')
          .height(52)
          .onClick(() => {
            lightHaptic()
            item.action()
          })
        }
        .width('100%')
      }, (item: NavItem, index: number) => `${item.labelKey}_${index}`)
    }
    .cardStyle()
  }

  @Builder
  SectionHeader(key: string) {
    Text(this.tr(key))
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.terminal_on_surface_variant'))
      .textCase(TextCase.UpperCase)
      .width('calc(100% - 32vp)')
      .padding({ left: 16 })
      .margin({ top: 20, bottom: 8 })
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
        Text(this.tr('security.edit_profile'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_on_surface'))
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

        Text(this.tr('security.change_avatar'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_primary_container'))
          .margin({ top: 8, bottom: 20 })

        Text(this.tr('security.display_name'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ bottom: 6 })

        TextInput({ text: this.editDisplayName, placeholder: this.tr('security.display_name') })
          .width('100%')
          .height(44)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .fontColor($r('app.color.terminal_on_surface'))
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
            Text(this.tr('common.save'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_on_primary'))
          }
        }
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor($r('app.color.terminal_primary'))
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
}

/** 分组卡片容器样式：surface_container 背景 + 12dp 圆角 + 16dp 水平内边距 */
@Extend(Column)
function cardStyle() {
  .width('calc(100% - 32vp)')
  .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  .borderRadius(12)
  .backgroundColor($r('app.color.terminal_surface_container'))
  .margin({ bottom: 8 })
}
