/** Worker activation entry: open the in-page QR camera, with manual code entry below. */
import { customScan, scanBarcode, scanCore } from '@kit.ScanKit'
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { AuthService, RouteName, I18n, PageLayout, showI18nToast, AnalyticsService, AnalyticsEvent, lightHaptic } from '@rwecho/core'

@Component
export struct ActivateWorkerPage {
  @State activationCode: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State successMessage: string = ''
  @State cameraGranted: boolean = false
  @State cameraMessage: string = ''
  @State previewLoaded: boolean = false
  @State previewWidth: number = 0
  @State previewHeight: number = 0
  @State isScanning: boolean = false
  @State surfaceId: string = ''
  @State isPageVisible: boolean = true
  private cameraController: XComponentController = new XComponentController()
  private permissionRequested: boolean = false
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('ActivateWorker')
    this.isPageVisible = true
    this.requestCameraPermission()
  }

  onPageShow() {
    this.isPageVisible = true
    this.startInlineScanner()
  }

  onPageHide() {
    this.isPageVisible = false
    this.releaseInlineScanner()
  }

  aboutToDisappear() {
    this.isPageVisible = false
    this.releaseInlineScanner()
  }

  build() {
    PageLayout({ title: I18n.get('auth.activate.title') }) {
      Column({ space: 18 }) {
        Column({ space: 6 }) {
          Text(I18n.get('auth.activate.hero_title'))
            .fontSize(25).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_text'))
          Text(I18n.get('auth.activate.hero_subtitle'))
            .fontSize(14).fontColor($r('app.color.terminal_text_muted'))
        }
        .width('100%').alignItems(HorizontalAlign.Start).margin({ top: 8 })

        if (this.successMessage.length > 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(48).fontColor([$r('app.color.terminal_success')])
            Text($r('app.string.activate_success')).fontSize(17)
              .fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_success'))
          }
          .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 44, bottom: 44 })
        } else {
          Column({ space: 14 }) {
            Stack({ alignContent: Alignment.Center }) {
              XComponent({
                id: 'worker_activation_camera_surface',
                type: XComponentType.SURFACE,
                controller: this.cameraController
              })
                .width('100%').height(336)
                .onLoad(() => {
                  this.surfaceId = this.cameraController.getXComponentSurfaceId()
                  this.previewLoaded = true
                  this.startInlineScanner()
                })
                .onDestroy(() => {
                  this.previewLoaded = false
                  this.surfaceId = ''
                })

              Column({ space: 10 }) {
                Text(I18n.get('auth.activate.scan_computer'))
                  .fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.terminal_camera_text'))
                Column() { }
                  .width(212).height(212).borderRadius(20)
                  .border({ width: 2, color: $r('app.color.terminal_primary') })
                Text(I18n.get('auth.activate.scan_hint'))
                  .fontSize(12).fontColor($r('app.color.terminal_camera_text'))
                  .textAlign(TextAlign.Center).maxLines(2)
              }
              .alignItems(HorizontalAlign.Center)
              .justifyContent(FlexAlign.Center)
              .width('100%').height(336)
              .backgroundColor(Color.Transparent)
            }
            .width('100%').height(336)
            .borderRadius(20).clip(true)
            .backgroundColor($r('app.color.terminal_background_element'))
            .border({ width: 1, color: $r('app.color.terminal_border_subtle') })
            .onAreaChange((_oldArea: Area, area: Area) => {
              this.previewWidth = area.width as number
              this.previewHeight = area.height as number
              this.startInlineScanner()
            })

            Row({ space: 8 }) {
              if (this.cameraGranted && this.cameraMessage.length === 0) {
                LoadingProgress().width(14).height(14).color($r('app.color.terminal_primary'))
              } else {
                SymbolGlyph($r('sys.symbol.camera'))
                  .fontSize(15).fontColor([this.cameraGranted ? $r('app.color.terminal_error') : $r('app.color.terminal_text_muted')])
              }
              Text(this.cameraMessage.length > 0 ? this.cameraMessage : I18n.get('auth.activate.camera_searching'))
                .fontSize(13)
                .fontColor(this.cameraMessage.length > 0 ? $r('app.color.terminal_error') : $r('app.color.terminal_text_muted'))
            }.width('100%').justifyContent(FlexAlign.Center).height(24)

            if (this.errorMessage.length > 0) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                  .fontSize(16).fontColor([$r('app.color.terminal_error')])
                Text(this.errorMessage).fontSize(13)
                  .fontColor($r('app.color.terminal_error')).layoutWeight(1)
              }.width('100%')
            }

            Row({ space: 12 }) {
              Divider().layoutWeight(1).color($r('app.color.terminal_border_subtle'))
              Text(I18n.get('auth.activate.or')).fontSize(12)
                .fontColor($r('app.color.terminal_text_muted'))
              Divider().layoutWeight(1).color($r('app.color.terminal_border_subtle'))
            }.width('100%').margin({ top: 2, bottom: 2 })

            Button() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.keyboard'))
                  .fontSize(19).fontColor([$r('app.color.terminal_text')])
                Column({ space: 3 }) {
                  Text(I18n.get('auth.activate.enter_code')).fontSize(15)
                    .fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text'))
                  Text(I18n.get('auth.activate.code_help_detail')).fontSize(12)
                    .fontColor($r('app.color.terminal_text_muted'))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14).fontColor([$r('app.color.terminal_text_muted')])
              }
              .width('100%').height(64).padding({ left: 16, right: 14 })
            }
            .width('100%').borderRadius(14)
            .backgroundColor($r('app.color.terminal_background_panel'))
            .border({ width: 1, color: $r('app.color.terminal_border_subtle') })
            .onClick(() => {
              lightHaptic()
              this.pageStack.pushPath({ name: RouteName.ACTIVATE_CODE })
            })

            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.lock'))
                .fontSize(12).fontColor([$r('app.color.terminal_text_muted')])
              Text(I18n.get('auth.activate.camera_privacy')).fontSize(11)
                .fontColor($r('app.color.terminal_text_muted'))
            }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 2 })
          }.width('100%')
        }
      }
      .width('100%').padding({ left: 20, right: 20, top: 4, bottom: 24 })
    }
  }

  private async requestCameraPermission() {
    if (this.permissionRequested) return
    this.permissionRequested = true
    this.cameraMessage = I18n.get('auth.activate.camera_permission_prompt')
    try {
      const context = getContext(this) as common.UIAbilityContext
      const manager = abilityAccessCtrl.createAtManager()
      const permission = await manager.requestPermissionsFromUser(context, ['ohos.permission.CAMERA'] as Array<Permissions>)
      this.cameraGranted = permission.authResults.length > 0 && permission.authResults[0] === 0
      this.cameraMessage = this.cameraGranted ? '' : I18n.get('auth.activate.camera_denied')
      this.startInlineScanner()
    } catch (e) {
      const error = e as BusinessError
      this.cameraGranted = false
      this.cameraMessage = error.message || I18n.get('auth.activate.camera_denied')
    }
  }

  /** Start the custom ScanKit stream after both permission and XComponent surface are ready. */
  private startInlineScanner() {
    if (!this.isPageVisible || !this.cameraGranted || !this.previewLoaded ||
      this.surfaceId.length === 0 || this.previewWidth <= 0 || this.previewHeight <= 0 || this.isScanning) return
    this.errorMessage = ''
    this.isScanning = true
    try {
      customScan.init({
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      })
      const view: customScan.ViewControl = {
        width: this.previewWidth,
        height: this.previewHeight,
        surfaceId: this.surfaceId
      }
      customScan.start(view).then((results: Array<scanBarcode.ScanResult>) => {
        this.isScanning = false
        customScan.release().then(() => { }).catch(() => { })
        if (results.length === 0) return
        const code = this.extractUserCode(results[0].originalValue)
        if (code.length === 0) {
          this.errorMessage = I18n.get('auth.activate.scan_invalid')
          setTimeout((): void => this.startInlineScanner(), 300)
          return
        }
        this.activationCode = this.formatCode(code)
        this.activate()
      }).catch((e: BusinessError) => {
        this.isScanning = false
        this.errorMessage = e.message || I18n.get('auth.activate.scan_failed')
        customScan.release().then(() => { }).catch(() => { })
      })
    } catch (e) {
      const error = e as BusinessError
      this.isScanning = false
      this.errorMessage = error.message || I18n.get('auth.activate.scan_failed')
    }
  }

  private releaseInlineScanner() {
    if (!this.isScanning) return
    this.isScanning = false
    customScan.release().then(() => { }).catch(() => { })
  }

  private extractUserCode(raw: string): string {
    if (!raw) return ''
    const match = raw.match(/[?&]code=([A-Za-z0-9-]+)/)
    const candidate = match !== null ? match[1] : raw.trim()
    const cleaned = candidate.toUpperCase().replace(/[^A-Z0-9]/g, '')
    return cleaned.length >= 4 ? cleaned.substring(0, 8) : ''
  }

  private formatCode(cleaned: string): string {
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
      setTimeout(() => AuthService.finishWorkerActivation(this.pageStack, RouteName.ACTIVATE_WORKER), 1000)
    }).catch((err: Error) => {
      this.errorMessage = err.message || I18n.get('common.error')
      this.isLoading = false
      setTimeout((): void => this.startInlineScanner(), 300)
    })
  }
}
