/**
 * @file ContactSupportPage.ets
 * @brief Lists support channels (QQ group / Telegram group / email) served by gateway.
 *
 * Pulls /api/support/info on enter. Each enabled group renders as a card with
 * group id / link (copyable via pasteboard) and a QR code image loaded from the
 * gateway. Domestic gateway returns only qqGroup, overseas only telegramGroup;
 * the app does not decide region — it just renders whatever the gateway returns.
 */
import { pasteboard } from '@kit.BasicServicesKit'
import {
  ApiService,
  I18n,
  PageLayout,
  RouteName,
  SupportGroupInfo,
  SupportInfo,
  showI18nToast,
  showToast,
  lightHaptic,
  clickHaptic,
  AnalyticsService,
  AnalyticsEvent
} from '@rwecho/core'

@Component
export struct ContactSupportPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State supportInfo: SupportInfo | null = null
  @State loadError: string = ''
  @State isLoading: boolean = true

  async aboutToAppear() {
    AnalyticsService.onPageStart('support/Contact')
    AnalyticsService.onEvent(AnalyticsEvent.VIEW_SUPPORT)
    await this.loadSupportInfo()
  }

  private async loadSupportInfo() {
    this.isLoading = true
    this.loadError = ''
    try {
      this.supportInfo = await ApiService.getSupportInfo()
    } catch (e) {
      // 异常即信号：把错误暴露给用户，不静默降级
      this.loadError = (e as Error).message || I18n.get('support.load_failed')
    } finally {
      this.isLoading = false
    }
  }

  build() {
    PageLayout({ title: I18n.get('support.title') }) {
      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color($r('app.color.terminal_on_surface_variant'))
          }
          .width('100%')
          .padding({ top: 80 })
          .alignItems(HorizontalAlign.Center)
        } else if (this.loadError.length > 0) {
          this.ErrorState()
        } else if (this.supportInfo !== null) {
          this.Content()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 24, right: 24, top: 8 })
    }
  }

  @Builder
  ErrorState() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(40)
        .fontColor([$r('app.color.terminal_error')])
      Text(I18n.get('support.load_failed'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 12 })
      Text(this.loadError)
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 4 })
        .textAlign(TextAlign.Center)
      Button(I18n.get('common.retry'))
        .type(ButtonType.Capsule)
        .height(40)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .margin({ top: 16 })
        .onClick(() => {
          clickHaptic()
          this.loadSupportInfo()
        })
    }
    .width('100%')
    .padding({ top: 60 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  Content() {
    Scroll() {
      Column() {
        if (this.supportInfo!.qqGroup !== null) {
          this.GroupCard(this.supportInfo!.qqGroup as SupportGroupInfo, false)
        }
        if (this.supportInfo!.telegramGroup !== null) {
          this.GroupCard(this.supportInfo!.telegramGroup as SupportGroupInfo, true)
        }
        if (this.supportInfo!.email.length > 0) {
          this.EmailCard(this.supportInfo!.email)
        }
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  @Builder
  GroupCard(group: SupportGroupInfo, isTelegram: boolean) {
    Column() {
      Row() {
        SymbolGlyph(isTelegram ? $r('sys.symbol.paperplane') : $r('sys.symbol.person_2'))
          .fontSize(20)
          .fontColor([$r('app.color.terminal_secondary')])
        Text(group.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Text(isTelegram ? group.url : group.number)
          .fontSize(14)
          .fontColor($r('app.color.terminal_secondary'))
          .layoutWeight(1)
        Text(I18n.get('support.copy'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_secondary_container'))
          .onClick(() => {
            clickHaptic()
            this.copyToClipboard(isTelegram ? group.url : group.number)
          })
      }
      .width('100%')
      .margin({ top: 12 })

      Column() {
        Image(group.qrCodeUrl)
          .width(160)
          .height(160)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .objectRepeat(ImageRepeat.NoRepeat)
        Text(I18n.get('support.scan_to_join'))
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 16 })

      if (isTelegram) {
        Button(I18n.get('support.open_tg'))
          .type(ButtonType.Capsule)
          .width('100%')
          .height(40)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .margin({ top: 12 })
          .onClick(() => {
            clickHaptic()
            this.openExternal(group.url)
          })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ bottom: 12 })
  }

  @Builder
  EmailCard(email: string) {
    Row() {
      SymbolGlyph($r('sys.symbol.envelope'))
        .fontSize(20)
        .fontColor([$r('app.color.terminal_secondary')])
      Text(email)
        .fontSize(14)
        .fontColor($r('app.color.terminal_primary'))
        .layoutWeight(1)
        .margin({ left: 8 })
      Text(I18n.get('support.copy'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.terminal_secondary_container'))
        .onClick(() => {
          clickHaptic()
          this.copyToClipboard(email)
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
  }

  private async copyToClipboard(text: string) {
    if (text.length === 0) {
      return
    }
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await systemPasteboard.setData(pasteData)
      showI18nToast('support.copied')
    } catch (e) {
      showToast((e as Error).message || I18n.get('common.error'))
    }
  }

  private openExternal(url: string) {
    const navParam: Record<string, string> = { 'url': url }
    this.pageStack.pushPath({ name: RouteName.WEB_PAGE, param: navParam })
  }
}
