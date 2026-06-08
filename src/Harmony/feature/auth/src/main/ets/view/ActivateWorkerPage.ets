/**
 * @file ActivateWorkerPage.ets
 * @brief Worker activation page with card layout and success state.
 */
import { AuthService, I18n } from '@rwecho/core'

@Component
export struct ActivateWorkerPage {
  @State activationCode: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack

  build() {
    Scroll() {
      Column() {
        // Brand
        Column() {
          Image($r('app.media.app_icon'))
            .width(64)
            .height(64)
            .borderRadius(16)
            .margin({ bottom: 16 })

          Text($r('app.string.activate_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))

          Text($r('app.string.activate_subtitle'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ top: 60 })

        // Success state
        if (this.successMessage.length > 0) {
          Column() {
            Text('✓')
              .fontSize(48)
              .fontColor($r('app.color.terminal_tertiary'))
            Text($r('app.string.activate_success'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_tertiary'))
              .margin({ top: 12 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 32 })
        } else {
          // Activation form card
          Column() {
            Text($r('app.string.activate_code_label'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 8 })

            TextInput({ placeholder: $r('app.string.activate_code_placeholder'), text: this.activationCode })
              .width('100%')
              .height(48)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
              .fontColor($r('app.color.terminal_primary'))
              .placeholderColor($r('app.color.terminal_on_surface_variant'))
              .onChange((value: string) => {
                this.activationCode = value.toUpperCase().replace(/[^A-Z0-9-]/g, '')
                this.errorMessage = ''
              })

            // Error message inside card
            if (this.errorMessage.length > 0) {
              Row() {
                Text('⚠')
                  .fontSize(14)
                  .fontColor($r('app.color.terminal_error'))
                  .margin({ right: 8 })
                Text(this.errorMessage)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.terminal_error'))
                  .layoutWeight(1)
              }
              .width('100%')
              .margin({ top: 12 })
            }

            Button() {
              if (this.isLoading) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color($r('app.color.terminal_on_secondary_container'))
              } else {
                Text($r('app.string.activate_button'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.terminal_on_secondary_container'))
              }
            }
            .width('100%')
            .height(48)
            .borderRadius(8)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .margin({ top: 20 })
            .enabled(!this.isLoading && this.activationCode.length > 0)
            .onClick(() => {
              this.activate()
            })
          }
          .width('100%')
          .padding(20)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ top: 32, left: 24, right: 24 })
        }

        // Skip link
        Text($r('app.string.activate_skip'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_secondary'))
          .margin({ top: 24 })
          .onClick(() => {
            AuthService.navigateHome(this.pageStack)
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
    .scrollBar(BarState.Off)
  }

  private activate() {
    if (this.activationCode.length === 0 || this.isLoading) {
      return
    }
    this.isLoading = true
    this.errorMessage = ''

    AuthService.activateWorker(this.activationCode).then(() => {
      this.isLoading = false
      this.successMessage = I18n.get('auth.activate.success')
      setTimeout(() => {
        AuthService.navigateHome(this.pageStack)
      }, 1000)
    }).catch((err: Error) => {
      this.errorMessage = err.message || 'Activation failed'
      this.isLoading = false
    })
  }
}
