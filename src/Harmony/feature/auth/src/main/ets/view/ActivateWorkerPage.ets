/**
 * @file ActivateWorkerPage.ets
 * @brief Worker activation code input page
 *
 * Allows the user to enter an activation code to bind their
 * worker machine to their account.
 */
import { AuthService } from '../service/AuthService'

@Component
export struct ActivateWorkerPage {
  @State activationCode: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  private authService: AuthService = new AuthService()

  build() {
    Scroll() {
      Column() {
        // Header
        Column() {
          Text('Activate Worker')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))
            .margin({ bottom: 8 })

          Text('Enter the activation code from your worker machine')
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .textAlign(TextAlign.Center)
            .margin({ bottom: 32 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ top: 40 })

        // Activation code input
        Column() {
          Text('Activation Code')
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .width('100%')
            .margin({ bottom: 8 })

          TextInput({ placeholder: 'Enter activation code', text: this.activationCode })
            .width('100%')
            .height(48)
            .borderRadius(12)
            .backgroundColor($r('app.color.terminal_surface_container'))
            .fontColor($r('app.color.terminal_primary'))
            .onChange((value: string) => {
              this.activationCode = value
              this.errorMessage = ''
              this.successMessage = ''
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })

        // Error message
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor($r('app.color.terminal_error'))
            .width('100%')
            .padding({ left: 24, right: 24 })
            .margin({ top: 12 })
        }

        // Success message
        if (this.successMessage.length > 0) {
          Text(this.successMessage)
            .fontSize(13)
            .fontColor($r('app.color.terminal_tertiary'))
            .width('100%')
            .padding({ left: 24, right: 24 })
            .margin({ top: 12 })
        }

        // Activate button
        Button('Activate')
          .width('calc(100% - 48vp)')
          .height(48)
          .margin({ top: 24 })
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.isLoading && this.activationCode.length > 0)
          .onClick(() => {
            this.activate()
          })

        // Skip for now
        Text('Skip for now')
          .fontSize(14)
          .fontColor($r('app.color.terminal_secondary'))
          .margin({ top: 16 })
          .onClick(() => {
            this.authService.completeAuth()
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private activate() {
    if (this.activationCode.length === 0 || this.isLoading) {
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    this.successMessage = ''

    this.authService.activateWorker(this.activationCode).then(() => {
      this.isLoading = false
      this.successMessage = 'Worker activated successfully!'
      // Navigate to terminal home after a brief delay
      setTimeout(() => {
        this.authService.completeAuth()
      }, 1000)
    }).catch((err: Error) => {
      this.errorMessage = err.message || 'Activation failed'
      this.isLoading = false
    })
  }
}
