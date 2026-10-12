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

/** 无字节的宽限期：到点仍无进度/完成即判端点不可达，交给协商链的下一端点。 */
export const ENDPOINT_STALL_MS: number = 6000
/** 公网/Relay 端点：首字节要经 relay↔worker 配对，宽限期放大。 */
export const REMOTE_STALL_MS: number = 30000

export class FileDownloader {
  /** 下载到沙箱；返回实际落盘路径（目标被占时 resolveAvailablePath 会改名）。 */
  static async download(context: Context, targetPath: string, downloadUrl: string,
    stallMs: number = ENDPOINT_STALL_MS): Promise<string> {
    const finalPath = FileDownloader.resolveAvailablePath(targetPath)
    return new Promise<string>((resolve, reject) => {
      // DownloadTask 没有 'fail' 事件（见头注释）：对不可达主机（如远端 worker 的
      // LAN 地址）任务创建成功后只会永远挂着，协商链就此卡死、永远到不了 Relay。
      // 所以用“停滞检测”兜底——建任务后 stallMs 内没有任何进度或完成事件就删除
      // 任务并拒绝，让调用方落到下一个端点。一旦有进度即解除看门狗，大文件的慢速
      // 传输不受影响。
      let settled = false
      let task: request.DownloadTask | undefined = undefined
      const settle = (fn: () => void) => {
        if (settled) {
          return
        }
        settled = true
        clearTimeout(watchdog)
        fn()
      }
      const watchdog = setTimeout(() => {
        try {
          task?.delete()
        } catch (_e) {
          // 任务已自行结束——以 complete 的 settle 为准。
        }
        settle(() => reject(new Error(`endpoint unreachable (no bytes for ${Math.round(stallMs / 1000)}s)`)))
      }, stallMs)
      request.downloadFile(context, { url: downloadUrl, filePath: finalPath })
        .then((t) => {
          if (settled) {
            return
          }
          task = t
          t.on('progress', (received: number, _total: number) => {
            // 只有真字节（received > 0）才证明链路通：任务创建时会先发 (0,0)，
            // 那不算进度，不能解除停滞看门狗。
            if (received > 0) {
              clearTimeout(watchdog)
            }
          })
          t.on('complete', () => settle(() => resolve(finalPath)))
        })
        .catch((err: BusinessError) => {
          settle(() => reject(new Error(err.message || 'Download failed')))
        })
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
