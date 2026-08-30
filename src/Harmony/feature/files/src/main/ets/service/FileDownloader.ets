/**
 * @file FileDownloader.ets
 * @brief Downloads via @ohos.request.downloadFile into the app sandbox.
 *
 * Files land in `${filesDir}/downloads/${filename}`. request.downloadFile fails when the
 * target already exists, so an existing file is renamed to `name(1).ext` first.
 *
 * Note: DownloadTask.on in current SDK exposes 'progress'/'complete'/'pause'/
 * 'remove' only — no 'fail' event. Task creation / config failures surface via
 * the downloadFile() promise rejection below.
 */
import request from '@ohos.request'
import fs from '@ohos.file.fs'
import { BusinessError } from '@ohos.base'

export class FileDownloader {
  static async download(context: Context, targetPath: string, downloadUrl: string): Promise<void> {
    const finalPath = FileDownloader.resolveAvailablePath(targetPath)
    return new Promise<void>((resolve, reject) => {
      request.downloadFile(context, { url: downloadUrl, filePath: finalPath })
        .then((task) => {
          task.on('complete', () => resolve())
        })
        .catch((err: BusinessError) => reject(new Error(err.message || 'Download failed')))
    })
  }

  /** `name.ext` → `name(1).ext` when the target is taken, `name(2).ext` when (1) is taken, ... */
  static resolveAvailablePath(targetPath: string): string {
    if (!fs.accessSync(targetPath)) {
      return targetPath
    }
    const slashIdx = targetPath.lastIndexOf('/')
    const dir = slashIdx >= 0 ? targetPath.substring(0, slashIdx + 1) : ''
    const filename = slashIdx >= 0 ? targetPath.substring(slashIdx + 1) : targetPath
    const dotIdx = filename.lastIndexOf('.')
    const stem = dotIdx > 0 ? filename.substring(0, dotIdx) : filename
    const ext = dotIdx > 0 ? filename.substring(dotIdx) : ''
    for (let n = 1; n < 1000; n++) {
      const candidate = `${dir}${stem}(${n})${ext}`
      if (!fs.accessSync(candidate)) {
        return candidate
      }
    }
    throw new Error('download directory is full of conflicting files')
  }
}
