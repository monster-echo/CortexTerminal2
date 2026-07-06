/**
 * @file AvatarPicker.ets
 * @brief Photo album picker + base64 reader for avatar uploads.
 *
 * Wraps @ohos.file.picker.PhotoViewPicker (image-only, single select) and
 * reads the chosen file as a base64 data URL for POST /api/me/avatar.
 * Returns an empty string from readAsBase64() when the file exceeds 2MB,
 * so callers can surface the avatar_too_large message.
 */
import picker from '@ohos.file.picker'
import fs from '@ohos.file.fs'
import { buffer } from '@kit.ArkTS'

const MAX_AVATAR_BYTES = 2 * 1024 * 1024

export class AvatarPicker {
  static async pickSingle(): Promise<string> {
    const options = new picker.PhotoSelectOptions()
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = 1
    const viewer = new picker.PhotoViewPicker()
    const result = await viewer.select(options)
    if (result.photoUris.length > 0) {
      return result.photoUris[0]
    }
    return ''
  }

  static async readAsBase64(uri: string): Promise<string> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    try {
      const stat = fs.statSync(file.fd)
      if (stat.size > MAX_AVATAR_BYTES) {
        return ''
      }
      const arrayBuffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, arrayBuffer)
      const encoded = buffer.from(arrayBuffer).toString('base64')
      const ext = uri.substring(uri.lastIndexOf('.') + 1).toLowerCase()
      const contentType = ext === 'jpg' || ext === 'jpeg'
        ? 'image/jpeg'
        : ext === 'webp' ? 'image/webp' : 'image/png'
      return `data:${contentType};base64,${encoded}`
    } finally {
      fs.closeSync(file)
    }
  }
}
