/**
 * @file SliderCaptchaDialog.ets
 * @brief Slider puzzle captcha dialog used when backend returns CAPTCHA_REQUIRED.
 *
 * Flow:
 *  1. aboutToAppear → loadChallenge() pulls challenge and decodes two PNGs to PixelMap
 *  2. User drags the handle → PanGesture updates sliderX (clamped to [0, MAX_X])
 *  3. onActionEnd → verify(id, round(sliderX))
 *      - Success → feedback='success' → onSuccess(token) → controller.close()
 *      - Failure → feedback='failed' → 800ms later loadChallenge() (old id consumed)
 */
import { AuthService, I18n } from '@rwecho/core'
import { image } from '@kit.ImageKit'
import { util } from '@kit.ArkTS'
import { CaptchaChallenge } from '../model/AuthModels'

const IMAGE_WIDTH: number = 300
const IMAGE_HEIGHT: number = 180
const PIECE_SIZE: number = 44
const MAX_X: number = IMAGE_WIDTH - PIECE_SIZE  // 256
const DIALOG_WIDTH: number = 336

@CustomDialog
export struct SliderCaptchaDialog {
  controller: CustomDialogController
  onSuccess: (token: string) => void = () => {}
  onCancel: () => void = () => {}

  @State challenge: CaptchaChallenge | null = null
  @State bgPixelMap: PixelMap | null = null
  @State sliderPixelMap: PixelMap | null = null
  @State sliderX: number = 0
  @State isLoading: boolean = false
  @State loadError: boolean = false
  @State isVerifying: boolean = false
  @State feedback: string = 'idle'  // 'idle' | 'success' | 'failed'

  private dragStartLocalX: number = 0
  private sliderStartX: number = 0

  aboutToAppear() {
    this.loadChallenge()
  }

  aboutToDisappear() {
    this.releasePixelMaps()
  }

  build() {
    Column() {
      // ── Header ──
      Row() {
        Text(I18n.get('auth.captcha.title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
        Text('✕')
          .fontSize(18)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .onClick(() => {
            this.onCancel()
            this.controller.close()
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 20, bottom: 16 })

      // ── Captcha image ──
      Stack() {
        if (this.bgPixelMap !== null) {
          Image(this.bgPixelMap)
            .width(IMAGE_WIDTH)
            .height(IMAGE_HEIGHT)
            .objectFit(ImageFit.Fill)
            .position({ x: 0, y: 0 })
        }
        if (this.sliderPixelMap !== null && this.bgPixelMap !== null) {
          Image(this.sliderPixelMap)
            .width(IMAGE_WIDTH)
            .height(IMAGE_HEIGHT)
            .objectFit(ImageFit.Fill)
            .position({ x: this.sliderX, y: 0 })
        }
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(32)
              .height(32)
              .color($r('app.color.terminal_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
        }
        if (this.loadError && !this.isLoading) {
          Column() {
            Text(I18n.get('auth.captcha.load_failed'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_error'))
            Button(I18n.get('common.retry'))
              .margin({ top: 8 })
              .fontSize(13)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .borderRadius(16)
              .height(32)
              .onClick(() => {
                this.loadChallenge()
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
        }
      }
      .width(IMAGE_WIDTH)
      .height(IMAGE_HEIGHT)
      .borderRadius(8)
      .clip(true)
      .margin({ left: 18, right: 18 })

      // ── Slider track ──
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width(this.sliderX + PIECE_SIZE)
          .height(PIECE_SIZE)
          .backgroundColor(this.trackFillColor())
          .borderRadius(PIECE_SIZE / 2)
          .position({ x: 0, y: 0 })

        Column() {
          Text(this.handleIcon())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.handleIconColor())
        }
        .width(PIECE_SIZE)
        .height(PIECE_SIZE)
        .backgroundColor($r('app.color.terminal_surface_container_highest'))
        .borderRadius(PIECE_SIZE / 2)
        .border({ width: 1.5, color: this.handleBorderColor() })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .position({ x: this.sliderX, y: 0 })
        .gesture(
          PanGesture()
            .onActionStart((e: GestureEvent) => {
              if (this.isVerifying || this.feedback === 'success' || this.feedback === 'failed') {
                return
              }
              this.dragStartLocalX = e.fingerList[0].localX
              this.sliderStartX = this.sliderX
            })
            .onActionUpdate((e: GestureEvent) => {
              if (this.isVerifying || this.feedback === 'success' || this.feedback === 'failed') {
                return
              }
              const delta = e.fingerList[0].localX - this.dragStartLocalX
              const newX = this.sliderStartX + delta
              this.sliderX = Math.max(0, Math.min(MAX_X, newX))
            })
            .onActionEnd(() => {
              if (this.isVerifying || this.feedback === 'success' || this.feedback === 'failed') {
                return
              }
              this.handleVerify()
            })
        )
      }
      .width(IMAGE_WIDTH)
      .height(PIECE_SIZE)
      .borderRadius(PIECE_SIZE / 2)
      .backgroundColor($r('app.color.terminal_surface_container_high'))
      .margin({ left: 18, right: 18, top: 16 })

      // ── Status text ──
      if (this.feedback === 'failed') {
        Text(I18n.get('auth.captcha.failed'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_error'))
          .margin({ top: 12, bottom: 4 })
      } else if (this.feedback === 'success') {
        Text(I18n.get('auth.captcha.success'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_tertiary'))
          .margin({ top: 12, bottom: 4 })
      } else if (this.isVerifying) {
        Row() {
          LoadingProgress()
            .width(14)
            .height(14)
            .color($r('app.color.terminal_on_surface_variant'))
          Text(I18n.get('auth.captcha.verifying'))
            .fontSize(13)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ left: 6 })
        }
        .margin({ top: 12, bottom: 4 })
      } else if (!this.isLoading && !this.loadError) {
        Text(I18n.get('auth.captcha.hint'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 12, bottom: 4 })
      }
    }
    .width(DIALOG_WIDTH)
    .padding({ bottom: 24 })
    .backgroundColor($r('app.color.terminal_surface_container_highest'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Center)
  }

  // ── Visual state helpers ──
  private trackFillColor(): ResourceColor {
    if (this.feedback === 'success') {
      return $r('app.color.terminal_tertiary')
    }
    if (this.feedback === 'failed') {
      return $r('app.color.terminal_error')
    }
    return $r('app.color.terminal_secondary_container')
  }

  private handleBorderColor(): ResourceColor {
    if (this.feedback === 'success') {
      return $r('app.color.terminal_tertiary')
    }
    if (this.feedback === 'failed') {
      return $r('app.color.terminal_error')
    }
    return $r('app.color.terminal_secondary_container')
  }

  private handleIconColor(): ResourceColor {
    if (this.feedback === 'success') {
      return $r('app.color.terminal_tertiary')
    }
    if (this.feedback === 'failed') {
      return $r('app.color.terminal_error')
    }
    return $r('app.color.terminal_on_surface_variant')
  }

  private handleIcon(): string {
    if (this.feedback === 'success') {
      return '✓'
    }
    if (this.feedback === 'failed') {
      return '✕'
    }
    return '→'
  }

  // ── Business logic ──
  private async loadChallenge() {
    this.isLoading = true
    this.loadError = false
    this.sliderX = 0
    this.feedback = 'idle'
    this.releasePixelMaps()
    try {
      const resp = await AuthService.getCaptchaChallenge()
      const c = new CaptchaChallenge()
      c.id = (resp['id'] as string) ?? ''
      c.backgroundImage = (resp['backgroundImage'] as string) ?? ''
      c.sliderImage = (resp['sliderImage'] as string) ?? ''
      c.y = (resp['y'] as number) ?? 0
      if (c.id.length === 0) {
        throw new Error('Empty captcha id')
      }
      this.challenge = c
      const results = await Promise.all<PixelMap>([
        base64ToPixelMap(c.backgroundImage),
        base64ToPixelMap(c.sliderImage)
      ])
      this.bgPixelMap = results[0]
      this.sliderPixelMap = results[1]
    } catch (e) {
      console.warn(`[Captcha] loadChallenge failed: ${(e as Error).message}`)
      this.loadError = true
    } finally {
      this.isLoading = false
    }
  }

  private async handleVerify() {
    const c = this.challenge
    if (c === null) {
      return
    }
    if (this.sliderX <= 0) {
      return
    }
    this.isVerifying = true
    try {
      const token = await AuthService.verifyCaptcha(c.id, Math.round(this.sliderX))
      this.isVerifying = false
      this.feedback = 'success'
      setTimeout(() => {
        this.onSuccess(token)
        this.controller.close()
      }, 500)
    } catch (e) {
      console.warn(`[Captcha] verify failed: ${(e as Error).message}`)
      this.isVerifying = false
      this.feedback = 'failed'
      setTimeout(() => {
        this.loadChallenge()
      }, 800)
    }
  }

  private releasePixelMaps() {
    if (this.bgPixelMap !== null) {
      this.bgPixelMap.release()
      this.bgPixelMap = null
    }
    if (this.sliderPixelMap !== null) {
      this.sliderPixelMap.release()
      this.sliderPixelMap = null
    }
  }
}

/**
 * Decode raw base64 PNG (no data URI prefix) into a PixelMap.
 */
async function base64ToPixelMap(b64: string): Promise<PixelMap> {
  const helper = new util.Base64Helper()
  const bytes: Uint8Array = helper.decodeSync(b64)
  const imageSource: image.ImageSource = image.createImageSource(bytes.buffer)
  return await imageSource.createPixelMap()
}
