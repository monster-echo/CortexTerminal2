import { webview } from '@kit.ArkWeb'
import { clickHaptic } from '@rwecho/core'

@Component
export struct WebPage {
  @Consume('pageStack') pageStack: NavPathStack
  webviewController: webview.WebviewController = new webview.WebviewController()
  @State pageTitle: string = ''
  @State url: string = ''

  aboutToAppear() {
    const params = this.pageStack.getParamByName('web/Page') as Record<string, string>[]
    if (params && params.length > 0) {
      const last = params[params.length - 1]
      this.url = last['url'] || ''
      this.pageTitle = last['title'] || ''
    }
  }

  build() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(40).height(40).borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          clickHaptic()
          this.pageStack.pop()
        })

        Text(this.pageTitle.length > 0 ? this.pageTitle : this.url)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })
      }
      .width('100%').height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      Web({ src: this.url, controller: this.webviewController })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .zoomAccess(true)
        .onTitleReceive((e) => {
          if (e && e.title.length > 0 && this.pageTitle.length === 0) {
            this.pageTitle = e.title
          }
        })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }
}
