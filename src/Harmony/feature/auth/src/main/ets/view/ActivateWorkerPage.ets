/**
 * @file ActivateWorkerPage.ets
 * @brief Worker activation page with card layout and success state.
 *
 * Two entry paths: scan the QR shown by the desktop app (ScanKit, preferred —
 * the QR encodes the activation URL whose ?code= param is the user code), or
 * type the XXXX-XXXX code manually.
 */
import { scanBarcode } from '@kit.ScanKit'
import { common, abilityAccessCtrl, Permissions, BusinessError } from '@kit.AbilityKit'
import { AuthService, I18n, PageLayout, showI18nToast, AnalyticsService, AnalyticsEvent } from '@rwecho/core'

@Component
export struct ActivateWorkerPage {
  @State activationCode: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  @State isScanning: boolean = false
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('ActivateWorker')
  }

  build() {
    PageLayout({ title: I18n.get('auth.activate.title') }) {
        Column() {
          // Brand
          Column() {
            Image($r('app.media.app_icon'))
              .width(64)
              .height(64)
              .borderRadius(16)
              .margin({ bottom: 16 })

            Text($r('app.string.activate_subtitle'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .textAlign(TextAlign.Center)
              .margin({ top: 8 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 8 })

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
                  const cleaned = value.toUpperCase().replace(/[^A-Z0-9]/g, '')
                  let formatted = ''
                  for (let i = 0; i < cleaned.length && i < 8; i++) {
                    if (i > 0 && i % 4 === 0) {
                      formatted += '-'
                    }
                    formatted += cleaned[i]
                  }
                  this.activationCode = formatted
                  this.errorMessage = ''
                })

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
                if (this.isScanning) {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                    .color($r('app.color.terminal_on_secondary_container'))
                } else {
                  Text(I18n.get('auth.activate.scan'))
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.terminal_on_secondary_container'))
                }
              }
              .width('100%')
              .height(48)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .margin({ top: 12 })
              .enabled(!this.isScanning && !this.isLoading)
              .onClick(() => {
                this.startScan()
              })

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
            .margin({ top: 32 })
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
      }
  }

  /**
   * Scan the QR displayed by the desktop app. The QR payload is the activation
   * URL (`<gateway>/activate?code=XXXX-XXXX`); extract the code param. A bare
   * user code is accepted too. Camera permission is requested inline — the
   * scan page cannot open without it.
   */
  private async startScan() {
    if (this.isScanning) {
      return
    }
    this.isScanning = true
    this.errorMessage = ''
    try {
      const context = getContext(this) as common.UIAbilityContext
      const manager = abilityAccessCtrl.createAtManager()
      await manager.requestPermissionsFromUser(context, ['ohos.permission.CAMERA'] as Array<Permissions>)

      const options = new scanBarcode.ScanOptions()
      options.scanTypes = [scanBarcode.ScanType.QR_CODE]
      const result = await scanBarcode.startScanForResult(context, options)
      const code = this.extractUserCode(result.originalValue)
      if (code.length === 0) {
        this.errorMessage = I18n.get('auth.activate.scan_invalid')
        return
      }
      this.activationCode = this.formatCode(code)
      this.activate()
    } catch (e) {
      const err = e as BusinessError
      // 用户取消扫码（result code 1001）不算错误，静默返回
      if (err.code !== 1001) {
        this.errorMessage = err.message || I18n.get('auth.activate.scan_failed')
      }
    } finally {
      this.isScanning = false
    }
  }

  /** Extract the user code from a URL's `code` query param, or accept a raw code. */
  private extractUserCode(raw: string): string {
    if (!raw) {
      return ''
    }
    const match = raw.match(/[?&]code=([A-Za-z0-9-]+)/)
    const candidate = match !== null ? match[1] : raw.trim()
    const cleaned = candidate.toUpperCase().replace(/[^A-Z0-9]/g, '')
    return cleaned.length >= 4 ? cleaned.substring(0, 8) : ''
  }

  private formatCode(cleaned: string): string {
    let formatted = ''
    for (let i = 0; i < cleaned.length && i < 8; i++) {
      if (i > 0 && i % 4 === 0) {
        formatted += '-'
      }
      formatted += cleaned[i]
    }
    return formatted
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
      AnalyticsService.onEvent(AnalyticsEvent.WORKER_ACTIVATE)
      showI18nToast('auth.activate_success')
      setTimeout(() => {
        AuthService.navigateHome(this.pageStack)
      }, 1000)
    }).catch((err: Error) => {
      this.errorMessage = err.message || 'Activation failed'
      this.isLoading = false
    })
  }
}
