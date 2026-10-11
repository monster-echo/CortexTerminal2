/** Manual-code path for adding a Worker to the account. */
import { AuthService, RouteName, I18n, PageLayout, showI18nToast, AnalyticsService, AnalyticsEvent } from '@rwecho/core'

@Component
export struct EnterActivationCodePage {
  @Prop initialCode: string = ''
  @State activationCode: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('EnterActivationCode')
    if (this.initialCode.length > 0) {
      this.activationCode = this.formatCode(this.initialCode)
      this.activate()
    }
  }

  build() {
    PageLayout({ title: I18n.get('auth.activate.code_title') }) {
      Column({ space: 20 }) {
        if (this.successMessage.length === 0) {
          Text(I18n.get('auth.activate.code_help_detail')).fontSize(14)
            .fontColor($r('app.color.terminal_text_muted')).width('100%')
        }

        if (this.successMessage.length > 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(48).fontColor([$r('app.color.terminal_success')])
            Text(I18n.get('auth.activate.success')).fontSize(17)
              .fontColor($r('app.color.terminal_success'))
          }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 48, bottom: 48 })
        } else {
          Column({ space: 16 }) {
            TextInput({ placeholder: I18n.get('auth.activate.code_example'), text: this.activationCode })
              .width('100%').height(58).fontSize(22).fontWeight(FontWeight.Medium)
              .fontFamily('monospace').textAlign(TextAlign.Center).borderRadius(12)
              .backgroundColor($r('app.color.terminal_background_element'))
              .fontColor($r('app.color.terminal_text')).placeholderColor($r('app.color.terminal_text_muted'))
              .accessibilityText(I18n.get('auth.activate.code_title')).enabled(!this.isLoading)
              .onChange((value: string) => {
                this.activationCode = this.formatCode(value)
                this.errorMessage = ''
              })
            if (this.errorMessage.length > 0) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                  .fontSize(16).fontColor([$r('app.color.terminal_error')])
                Text(this.errorMessage).fontSize(13)
                  .fontColor($r('app.color.terminal_error')).layoutWeight(1)
              }.width('100%')
            }
            Button() {
              if (this.isLoading) {
                LoadingProgress().width(20).height(20).color($r('app.color.terminal_inverse_on_surface'))
              } else {
                Text(I18n.get('auth.activate.button')).fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.terminal_inverse_on_surface'))
              }
            }
            .width('100%').height(52).borderRadius(12)
            .backgroundColor($r('app.color.terminal_inverse_surface'))
            .enabled(this.activationCode.length === 9 && !this.isLoading)
            .onClick(() => this.activate())
          }.width('100%')
        }
      }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: 24 }).alignItems(HorizontalAlign.Start)
    }
  }

  private formatCode(value: string): string {
    const cleaned = value.toUpperCase().replace(/[^A-Z0-9]/g, '')
    let formatted = ''
    for (let i = 0; i < cleaned.length && i < 8; i++) {
      if (i > 0 && i % 4 === 0) formatted += '-'
      formatted += cleaned[i]
    }
    return formatted
  }

  private activate() {
    if (this.activationCode.length !== 9 || this.isLoading) return
    this.isLoading = true
    this.errorMessage = ''
    AuthService.activateWorker(this.activationCode).then(() => {
      this.isLoading = false
      this.successMessage = I18n.get('auth.activate.success')
      AnalyticsService.onEvent(AnalyticsEvent.WORKER_ACTIVATE)
      showI18nToast('auth.activate_success')
      setTimeout(() => AuthService.finishWorkerActivation(this.pageStack, RouteName.ACTIVATE_CODE), 1000)
    }).catch((err: Error) => {
      this.errorMessage = err.message || I18n.get('common.error')
      this.isLoading = false
    })
  }
}
