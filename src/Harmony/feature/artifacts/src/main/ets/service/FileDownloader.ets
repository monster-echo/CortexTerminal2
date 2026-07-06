/**
 * @file FileDownloader.ets
 * @brief Downloads via @ohos.request.downloadFile into the app sandbox.
 *
 * Files land in `${filesDir}/downloads/${filename}` and can be opened by
 * the system file manager.
 *
 * Note: DownloadTask.on in current SDK exposes 'progress'/'complete'/'pause'/
 * 'remove' only — no 'fail' event. Task creation / config failures surface via
 * the downloadFile() promise rejection below.
 */
import request from '@ohos.request'
import { BusinessError } from '@ohos.base'

export class FileDownloader {
  static async download(context: Context, targetPath: string, downloadUrl: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      request.downloadFile(context, { url: downloadUrl, filePath: targetPath })
        .then((task) => {
          task.on('complete', () => resolve())
        })
        .catch((err: BusinessError) => reject(new Error(err.message || 'Download failed')))
    })
  }
}
