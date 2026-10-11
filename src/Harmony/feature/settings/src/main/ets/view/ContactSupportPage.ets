/** Feishu support entry, configured by the gateway. */
import { common, Want } from '@kit.AbilityKit'
import {
  ApiService,
  I18n,
  PageLayout,
  RouteName,
  SupportGroupInfo,
  SupportInfo,
  showI18nToast,
  showToast,
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
      if (!this.supportInfo.feishuGroup || this.supportInfo.feishuGroup.url.length === 0) {
        this.loadError = I18n.get('support.feishu_unavailable')
      }
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
            LoadingProgress().width(40).height(40).color($r('app.color.terminal_text_muted'))
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
        .fontColor($r('app.color.terminal_text_muted'))
        .margin({ top: 12 })
      Text(this.loadError)
        .fontSize(12)
        .fontColor($r('app.color.terminal_text_muted'))
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
      Column({ space: 20 }) {
        if (this.supportInfo!.feishuGroup !== null) {
          Text(I18n.get('support.feishuGroupName')).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_text'))
          QRCode((this.supportInfo!.feishuGroup as SupportGroupInfo).url)
            .width(220).height(220)
            .color($r('app.color.terminal_qr_foreground'))
            .backgroundColor($r('app.color.terminal_qr_background'))
            .padding(12)
            .accessibilityText(I18n.get('support.scan_to_join'))
          Text(I18n.get('support.scan_to_join')).fontSize(13)
            .fontColor($r('app.color.terminal_text_muted')).textAlign(TextAlign.Center)
          Button(I18n.get('support.join_feishu'))
            .width('100%').height(48).borderRadius(12)
            .backgroundColor($r('app.color.terminal_inverse_surface'))
            .fontColor($r('app.color.terminal_inverse_on_surface'))
            .onClick(() => {
              clickHaptic()
              this.openLink((this.supportInfo!.feishuGroup as SupportGroupInfo).url)
            })
        }
      }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 16, bottom: 24 })
    }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
  }

  /** applink 优先拉起飞书 App，未安装时由系统落到浏览器。 */
  private async openLink(url: string) {
    try {
      const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      }
      await ctx.startAbility(want)
    } catch (e) {
      showToast(I18n.get('common.link_open_failed'))
    }
  }
}
