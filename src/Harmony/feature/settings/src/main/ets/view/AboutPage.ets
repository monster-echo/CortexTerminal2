/**
 * @file AboutPage.ets
 * @brief 关于我们二级页：App 图标 + 名称 + 版本号居中，协议入口卡片，底部版权
 */
import { common } from '@kit.AbilityKit'
import { I18n, PageLayout, RouteName, lightHaptic } from '@rwecho/core'

@Component
export struct AboutPage {
  @StorageLink('language') currentLanguage: string = 'en'
  @StorageLink('appVersion') appVersion: string = '1.0.0'
  @Consume('pageStack') pageStack: NavPathStack

  /** 响应式 i18n */
  private tr(key: string): string {
    return I18n.get(key) + (this.currentLanguage ? '' : '')
  }

  private openLegal(resourceKey: string) {
    lightHaptic()
    const url = (this.getUIContext()?.getHostContext() as common.UIAbilityContext)
      .resourceManager.getStringByNameSync(resourceKey)
    const navParam: Record<string, string> = { 'url': url }
    this.pageStack.pushPath({ name: RouteName.WEB_PAGE, param: navParam })
  }

  build() {
    PageLayout({ title: I18n.get('settings.about') }) {
      Column() {
        // App 图标 + 名称 + 版本号
        Column() {
          Image($r('app.media.app_icon'))
            .width(88)
            .height(88)
            .borderRadius(22)

          Text(this.tr('auth.login.tagline'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_on_surface'))
            .margin({ top: 16 })

          Text(this.tr('settings.about_version').replace('{v}', this.appVersion))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 32, bottom: 16 })

        Blank().height(24)

        // 协议入口
        Column() {
          Row() {
            Text(this.tr('settings.footer_terms'))
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.terminal_text_tertiary')])
          }
          .width('100%')
          .height(52)
          .onClick(() => {
            this.openLegal('terms_of_service_url')
          })

          Divider()
            .color($r('app.color.terminal_outline_variant'))

          Row() {
            Text(this.tr('settings.footer_privacy'))
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.terminal_text_tertiary')])
          }
          .width('100%')
          .height(52)
          .onClick(() => {
            this.openLegal('privacy_policy_url')
          })
        }
        .aboutCardStyle()

        Blank().layoutWeight(1)

        // 底部版权
        Text(this.tr('settings.copyright'))
          .fontSize(12)
          .fontColor($r('app.color.terminal_text_tertiary'))
          .margin({ bottom: 24 })
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Extend(Column)
function aboutCardStyle() {
  .width('calc(100% - 32vp)')
  .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  .borderRadius(12)
  .backgroundColor($r('app.color.terminal_surface_container'))
}
