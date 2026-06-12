import { webview } from '@kit.ArkWeb'
import { PageLayout } from '@rwecho/core'

@Component
export struct WebPage {
  @Consume('pageStack') pageStack: NavPathStack
  webviewController: webview.WebviewController = new webview.WebviewController()
  @State pageTitle: string = ''
  private url: string = ''

  aboutToAppear() {
    const params = this.pageStack.getParamByName('web/Page') as Record<string, string>[]
    if (params && params.length > 0) {
      const last = params[params.length - 1]
      this.url = last['url'] || ''
      this.pageTitle = last['title'] || ''
    }
  }

  build() {
    PageLayout({ title: this.pageTitle.length > 0 ? this.pageTitle : this.url }) {
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
  }
}
