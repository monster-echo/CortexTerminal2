/**
 * @file FeedbackFilePicker.ets
 * @brief Photo album picker for feedback attachments (screenshots / photos).
 *
 * Uses photoAccessHelper exclusively. PhotoViewPicker URIs are media-library
 * URIs (file://media/...) that @ohos.file.fs cannot read — only photoAccessHelper
 * can resolve them. MediaAssetManager.requestImageData streams the picked photo
 * as an ArrayBuffer via MediaAssetDataHandler.onDataPrepared.
 *
 * onDataPrepared is invoked by the system, which detaches `this` — so the
 * handler is an object literal with an arrow function (lexical closure over
 * resolve/fetchResult), with a processed flag guarding against duplicate callbacks.
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { dataSharePredicates } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@ohos.base'

const MAX_FILE_BYTES: number = 50 * 1024 * 1024 // 50 MB

export interface PickedFile {
  bytes: ArrayBuffer
  filename: string
  contentType: string
}

export class FeedbackFilePicker {
  static async pick(ctx: common.Context): Promise<PickedFile | null> {
    const options = new photoAccessHelper.PhotoSelectOptions()
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = 1
    const viewer = new photoAccessHelper.PhotoViewPicker()
    const result = await viewer.select(options)
    if (result.photoUris.length === 0) {
      return null
    }
    const uri = result.photoUris[0]

    const helper = photoAccessHelper.getPhotoAccessHelper(ctx)
    const predicates = new dataSharePredicates.DataSharePredicates()
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri)
    const fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [photoAccessHelper.PhotoKeys.TITLE],
      predicates: predicates
    }
    const fetchResult = await helper.getAssets(fetchOptions)
    const photoAsset = await fetchResult.getFirstObject()

    const data: ArrayBuffer = await new Promise<ArrayBuffer>((resolve, reject) => {
      let processed = false
      const handler: photoAccessHelper.MediaAssetDataHandler<ArrayBuffer> = {
        onDataPrepared: (d: ArrayBuffer, _map?: Map<string, string>): void => {
          if (processed) {
            return
          }
          processed = true
          fetchResult.close()
          resolve(d)
        }
      }
      const requestOptions: photoAccessHelper.RequestOptions = {
        deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE
      }
      photoAccessHelper.MediaAssetManager.requestImageData(ctx, photoAsset, requestOptions, handler)
        .catch((err: BusinessError) => {
          fetchResult.close()
          reject(new Error(err.message))
        })
    })

    if (data.byteLength > MAX_FILE_BYTES) {
      throw new Error('图片不能超过 50MB')
    }
    const ext = uri.substring(uri.lastIndexOf('.') + 1).toLowerCase()
    const contentType = ext === 'jpg' || ext === 'jpeg'
      ? 'image/jpeg'
      : ext === 'webp' ? 'image/webp' : 'image/png'
    const filename = `feedback-${Date.now()}.${ext.length > 0 ? ext : 'png'}`
    return { bytes: data, filename, contentType }
  }
}
