/**
 * @file AvatarPicker.ets
 * @brief Photo album picker + base64 reader for avatar uploads.
 *
 * Uses photoAccessHelper exclusively. PhotoViewPicker URIs are media-library
 * URIs (file://media/...) that @ohos.file.fs and @ohos.multimedia.image cannot
 * read (ENOENT / undefined) — only photoAccessHelper can resolve them.
 * MediaAssetManager.requestImageData streams the picked photo as an ArrayBuffer
 * via MediaAssetDataHandler.onDataPrepared; we base64-encode it for upload.
 *
 * NOTE: onDataPrepared is invoked by the system, which detaches `this` — so the
 * handler is an object literal with an arrow function (lexical closure over
 * resolve/fetchResult), not a class method. A processed flag guards against
 * duplicate callbacks double-closing fetchResult.
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { dataSharePredicates } from '@kit.ArkData'
import { buffer } from '@kit.ArkTS'
import { BusinessError } from '@ohos.base'

const MAX_AVATAR_BYTES = 2 * 1024 * 1024

export class AvatarPicker {
  static async pickSingle(): Promise<string> {
    const options = new photoAccessHelper.PhotoSelectOptions()
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = 1
    const viewer = new photoAccessHelper.PhotoViewPicker()
    const result = await viewer.select(options)
    if (result.photoUris.length > 0) {
      return result.photoUris[0]
    }
    return ''
  }

  static async readAsBase64(context: Context, uri: string): Promise<string> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context)
    const predicates = new dataSharePredicates.DataSharePredicates()
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri)
    const fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [photoAccessHelper.PhotoKeys.TITLE],
      predicates: predicates
    }
    const fetchResult = await helper.getAssets(fetchOptions)
    const photoAsset = await fetchResult.getFirstObject()

    return new Promise<string>((resolve, reject) => {
      let processed = false
      const handler: photoAccessHelper.MediaAssetDataHandler<ArrayBuffer> = {
        onDataPrepared: (data: ArrayBuffer, _map?: Map<string, string>): void => {
          if (processed) {
            return
          }
          processed = true
          fetchResult.close()
          if (data.byteLength > MAX_AVATAR_BYTES) {
            resolve('')
            return
          }
          const encoded = buffer.from(data).toString('base64')
          const ext = uri.substring(uri.lastIndexOf('.') + 1).toLowerCase()
          const contentType = ext === 'jpg' || ext === 'jpeg'
            ? 'image/jpeg'
            : ext === 'webp' ? 'image/webp' : 'image/png'
          resolve(`data:${contentType};base64,${encoded}`)
        }
      }
      const requestOptions: photoAccessHelper.RequestOptions = {
        deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE
      }
      photoAccessHelper.MediaAssetManager.requestImageData(context, photoAsset, requestOptions, handler)
        .catch((err: BusinessError) => {
          fetchResult.close()
          reject(new Error(err.message))
        })
    })
  }
}
