/**
 * @file ImagePreviewPage.ets
 * @brief Fullscreen QR/image preview pushed onto the NavPathStack.
 *
 * Tapping the QR image in ContactSupportPage pushes this page with { url }.
 * SaveButton (security component, permission-free) saves the image to the gallery.
 * Tap the image area or press back to pop.
 */
import { common } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { I18n, RouteName, showToast, showI18nToast, clickHaptic } from '@rwecho/core'

@Component
export struct ImagePreviewPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State url: string = ''

  aboutToAppear() {
    const params = this.pageStack.getParamByName(RouteName.IMAGE_PREVIEW) as Record<string, string>[]
    if (params && params.length > 0) {
      this.url = params[params.length - 1]['url'] ?? ''
    }
  }

  build() {
    Stack() {
      if (this.url.length > 0) {
        Image(this.url)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      }
      SaveButton({ buttonType: ButtonType.Circle })
        .position({ x: '68%', y: '84%' })
        .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
          if (result === SaveButtonOnClickResult.SUCCESS) {
            clickHaptic()
            this.saveQrToGallery(this.url)
              .then(() => { showI18nToast('support.saved') })
              .catch((e: Error) => { showToast(e.message || I18n.get('common.error')) })
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onClick(() => {
      clickHaptic()
      this.pageStack.pop()
    })
  }

  private async saveQrToGallery(url: string): Promise<void> {
    const httpRequest = http.createHttp()
    const data = await httpRequest.request(url, { expectDataType: http.HttpDataType.ARRAY_BUFFER })
    httpRequest.destroy()
    const buffer = data.result as ArrayBuffer
    const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx)
    const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png')
    const file = fs.openSync(uri, fs.OpenMode.READ_WRITE)
    fs.writeSync(file.fd, buffer)
    fs.closeSync(file)
  }
}
