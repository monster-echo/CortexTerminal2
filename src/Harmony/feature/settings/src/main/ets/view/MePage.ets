import { ApiService, AuthService, AuthState, I18n, RouteName, lightHaptic, showI18nToast } from '@rwecho/core'
import { ProfilePage } from './ProfilePage'

@Component
export struct MePage {
  @StorageLink('language') currentLanguage: string = 'en'
  @StorageLink('membershipRefreshTick') @Watch('refreshAccount') refreshTick: number = 0
  @StorageLink('userInfo') @Watch('refreshProfile') userInfo: string = ''
  @State displayName: string = ''
  @State avatarUrl: string = ''
  @State isPro: boolean = false
  @State expiresAtUtc: string = ''
  @State membershipLoaded: boolean = false
  @State error: string = ''
  @State showProfile: boolean = false
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() { this.refreshAccount() }

  refreshProfile() {
    this.displayName = AuthState.getDisplayName()
    this.avatarUrl = AuthState.getResolvedAvatarUrl()
  }

  async refreshAccount() {
    this.refreshProfile()
    this.error = ''
    try {
      const sub = await ApiService.getSubscription()
      this.isPro = sub['isActive'] as boolean
      this.expiresAtUtc = (sub['expiresAtUtc'] as string) ?? ''
      this.membershipLoaded = true
    } catch (e) {
      this.error = (e as Error).message
    }
  }

  private tr(key: string): string { return I18n.get(key) + (this.currentLanguage ? '' : '') }
  private open(route: string) { lightHaptic(); this.pageStack.pushPath({ name: route }) }

  private isExpiringSoon(): boolean {
    if (!this.isPro || this.expiresAtUtc.length === 0) return false
    const expires = new Date(this.expiresAtUtc).getTime()
    if (Number.isNaN(expires)) return false
    const remaining = expires - Date.now()
    return remaining > 0 && remaining <= 5 * 24 * 60 * 60 * 1000
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
          showI18nToast('settings.logout_success')
        }
      }
    })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          Row({ space: 12 }) {
            if (this.avatarUrl.length > 0) {
              Image(this.avatarUrl).width(52).height(52).borderRadius(26)
            } else {
              Text(this.displayName.substring(0, 1).toUpperCase())
                .width(52).height(52).textAlign(TextAlign.Center).fontSize(22)
                .fontColor($r('app.color.terminal_on_secondary_container'))
                .backgroundColor($r('app.color.terminal_secondary_container')).borderRadius(26)
            }
            Column({ space: 4 }) {
              Text(this.displayName).fontSize(20).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.terminal_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.tr('settings.profile')).fontSize(14).fontColor($r('app.color.terminal_text_muted'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.terminal_text_muted')])
          }
          .width('100%').padding(16).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
          .onClick(() => { this.showProfile = true })

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(24)
              .fontColor([this.isPro ? $r('app.color.terminal_success') : $r('app.color.terminal_text_muted')])
            Column({ space: 5 }) {
              Text(this.membershipLoaded ? this.tr(this.isPro ? 'membership.current_tier_pro' : 'membership.current_tier_free') : this.tr('account.membership_loading'))
                .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text'))
              Text(this.isPro ? (this.expiresAtUtc.length > 0 ? I18n.getWithArgs('membership.renews_expire', { 'date': this.expiresAtUtc.substring(0, 10) }) : this.tr('membership.plan_pro_lifetime')) : this.tr('account.view_pro'))
                .fontSize(14).fontColor($r('app.color.terminal_text_muted'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.terminal_text_muted')])
          }
          .width('100%').padding(16).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
          .onClick(() => this.open(RouteName.MEMBERSHIP))

          // 已是 Pro（含终身）时隐藏：兑换短期码会覆盖会员到期时间，造成降级
          if (!this.isPro) {
            Row() {
              Text(this.tr('settings.redeem_code_nav')).fontSize(16).fontColor($r('app.color.terminal_text')).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.terminal_text_muted')])
            }.width('100%').height(56).padding({ left: 16, right: 16 }).borderRadius(12)
            .backgroundColor($r('app.color.terminal_background_panel'))
            .onClick(() => this.open(RouteName.REDEEM))
          }

          if (this.isExpiringSoon()) {
            Text(I18n.getWithArgs('membership.renewal_reminder', {
              'plan': this.tr('membership.current_tier_pro'),
              'date': this.expiresAtUtc.substring(0, 10)
            }))
              .fontSize(13).fontColor($r('app.color.terminal_on_primary_container')).lineHeight(20)
              .width('100%').padding(12).borderRadius(12)
              .backgroundColor($r('app.color.terminal_primary_container'))
              .onClick(() => this.open(RouteName.MEMBERSHIP))
          }

          if (this.error.length > 0) {
            Text(this.error).fontSize(14).fontColor($r('app.color.terminal_error')).onClick(() => this.refreshAccount())
          }
          Column() {
            this.NavRow($r('sys.symbol.lock_shield'), 'settings.account_security', RouteName.ACCOUNT_SECURITY)
            Divider().color($r('app.color.terminal_border_subtle'))
            this.NavRow($r('sys.symbol.envelope'), 'settings.contact_support', RouteName.CONTACT_SUPPORT)
            Divider().color($r('app.color.terminal_border_subtle'))
            this.NavRow($r('sys.symbol.paperplane'), 'settings.feedback', RouteName.FEEDBACK)
            Divider().color($r('app.color.terminal_border_subtle'))
            this.NavRow($r('sys.symbol.info_circle'), 'settings.about', RouteName.ABOUT)
          }.padding({ left: 16, right: 16 }).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
        }.width('100%').padding(16)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)

      // 退出登录：从账号安全页移出，固定在我的页底部。
      Row() {
        Button(this.tr('settings.logout'))
          .width('100%').height(48)
          .fontColor($r('app.color.terminal_text'))
          .backgroundColor($r('app.color.terminal_background_panel'))
          .onClick(() => this.confirmLogout())
      }
      .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%').layoutWeight(1).backgroundColor($r('app.color.terminal_background'))
    .bindSheet(this.showProfile, this.ProfileEditor(), {
      height: SheetSize.LARGE, showClose: true, backgroundColor: $r('app.color.terminal_background'),
      onDisappear: () => { this.showProfile = false; this.refreshProfile() }
    })
  }

  @Builder
  ProfileEditor() {
    ProfilePage({ onSaved: () => { this.showProfile = false; this.refreshProfile() } })
  }

  @Builder
  NavRow(icon: Resource, key: string, route: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon).fontSize(20).fontColor([$r('app.color.terminal_text_muted')])
      Text(this.tr(key)).fontSize(16).fontColor($r('app.color.terminal_text')).layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.terminal_text_muted')])
    }.width('100%').height(56).onClick(() => this.open(route))
  }
}
