/**
 * @file FilesService.ets
 * @brief REST client for the workspace-scoped remote file flows (v2).
 *
 * Pure REST — no SignalR, no polling. Browsing is a live worker RPC via the Gateway;
 * upload/download get a signed transfer id plus candidate endpoints from the Gateway,
 * then stream bytes directly against the Relay (or a direct endpoint when present).
 */
import { ApiService, P2pTransfer, P2pPreparation, P2pChannel } from '@rwecho/core'
import fs from '@ohos.file.fs'
import { FileDownloader } from './FileDownloader'
import { TransferRouteLog } from './TransferRouteLog'
import { FileListingModel, WorkspaceModel, UploadInitModel, DownloadInitModel, TransferEndpointModel } from '../model/FileModels'

export class FilesService {
  /** List every workspace the signed-in user owns (across all workers). */
  static async listWorkspaces(): Promise<WorkspaceModel[]> {
    const response = await ApiService.listWorkspaces() as Record<string, Object>[]
    const models: WorkspaceModel[] = []
    for (let i = 0; i < response.length; i++) {
      models.push(WorkspaceModel.fromRecord(response[i]))
    }
    return models
  }

  static async createWorkspace(workerId: string, name: string, rootPath: string): Promise<WorkspaceModel> {
    const response = await ApiService.createWorkspace(workerId, name, rootPath)
    return WorkspaceModel.fromRecord(response)
  }

  /** List one directory under the given root ('' = root itself). */
  static async listFiles(workerId: string, root: string, path: string): Promise<FileListingModel> {
    const response = await ApiService.listFiles(workerId, root, path) as Record<string, Object>
    return FileListingModel.fromRecord(response)
  }

  /** List one directory of a workspace ('' = workspace root). Same listing shape as the worker-level browse. */
  static async listWorkspaceFiles(workspaceId: string, path: string): Promise<FileListingModel> {
    const response = await ApiService.listWorkspaceFiles(workspaceId, path) as Record<string, Object>
    return FileListingModel.fromRecord(response)
  }

  /** Workspace 级写操作：mkdir / 重命名 / 删除。失败直接抛出，由 UI 展示。 */
  static async mkdir(workspaceId: string, path: string): Promise<void> {
    await ApiService.workspaceMkdir(workspaceId, path)
  }

  static async rename(workspaceId: string, path: string, newName: string): Promise<void> {
    await ApiService.workspaceRename(workspaceId, path, newName)
  }

  static async deleteFile(workspaceId: string, path: string): Promise<void> {
    await ApiService.workspaceDeleteFile(workspaceId, path)
  }

  /** Upload step 1: register the transfer, get candidate endpoints. */
  static async beginUpload(workerId: string, root: string, dirPath: string, filename: string,
    sizeBytes: number, sha256: string): Promise<UploadInitModel> {
    const response = await ApiService.createFileUpload(workerId, root, dirPath, filename, sizeBytes, sha256)
    const model = new UploadInitModel()
    model.transferId = (response['transferId'] as string) ?? ''
    FilesService.readEndpoints(response, model.endpoints)
    return model
  }

  /** Download step 1: validate on the worker, get candidate endpoints. */
  static async startDownload(workerId: string, root: string, path: string): Promise<DownloadInitModel> {
    const response = await ApiService.startFileDownload(workerId, root, path)
    const model = new DownloadInitModel()
    model.transferId = (response['transferId'] as string) ?? ''
    model.sizeBytes = (response['sizeBytes'] as number) ?? 0
    model.filename = (response['filename'] as string) ?? ''
    FilesService.readEndpoints(response, model.endpoints)
    return model
  }

  private static readEndpoints(response: Record<string, Object>, into: TransferEndpointModel[]): void {
    const rawEndpoints = response['endpoints'] as Record<string, Object>[]
    if (rawEndpoints) {
      for (let i = 0; i < rawEndpoints.length; i++) {
        into.push(TransferEndpointModel.fromRecord(rawEndpoints[i]))
      }
    }
  }

  /**
   * 端点协商上传（规格 §5）：LAN → p2p（并行准备，6s 内打通才用）→ 公网 → Relay，
   * 任一端点成功即返回；全部失败抛出最后一次错误。
   */
  static async uploadViaEndpoints(transferId: string, endpoints: TransferEndpointModel[],
    buffer: ArrayBuffer): Promise<void> {
    await FilesService.transferViaEndpoints(transferId, endpoints, async (channel: P2pChannel, relayToken: string) => {
      await P2pTransfer.uploadP2p(channel, transferId, relayToken, buffer)
    }, async (url: string) => {
      await ApiService.putBinary(url, buffer)
    })
  }

  /**
   * 端点协商下载（规格 §5）：LAN → p2p → 公网 → Relay，逐个尝试 GET 下载到本地沙箱。
   */
  static async downloadViaEndpoints(context: Context, targetPath: string, transferId: string,
    endpoints: TransferEndpointModel[]): Promise<void> {
    await FilesService.transferViaEndpoints(transferId, endpoints, async (channel: P2pChannel, relayToken: string) => {
      await FilesService.downloadOverP2p(channel, transferId, relayToken, targetPath)
    }, async (url: string) => {
      await FileDownloader.download(context, targetPath, url)
    })
  }

  /**
   * 端点协商公共骨架：发起时并行启动 p2p 准备，尝试顺序 LAN → p2p（READY_WAIT_MS 内打通）
   * → 其余端点（公网 → Relay 按网关下发顺序）。p2p 失败静默落下一端点——这是规格允许的唯一回落。
   */
  private static async transferViaEndpoints(transferId: string, endpoints: TransferEndpointModel[],
    p2pFn: (channel: P2pChannel, relayToken: string) => Promise<void>,
    httpFn: (url: string) => Promise<void>): Promise<void> {
    if (endpoints.length === 0) {
      throw new Error('no transfer endpoints')
    }
    const lanEndpoints: TransferEndpointModel[] = []
    const restEndpoints: TransferEndpointModel[] = []
    for (let i = 0; i < endpoints.length; i++) {
      if (endpoints[i].kind.toLowerCase() === 'lan') {
        lanEndpoints.push(endpoints[i])
      } else {
        restEndpoints.push(endpoints[i])
      }
    }
    // p2p 与 LAN 并行准备（punch+STUN+探包可能要数秒）
    const relayToken = FilesService.relayTokenFromEndpoints(endpoints)
    const preparation: P2pPreparation | null =
      relayToken.length > 0 ? P2pTransfer.startPreparation(transferId, relayToken) : null

    let lastError = new Error('all transfer endpoints failed')
    for (let i = 0; i < lanEndpoints.length; i++) {
      try {
        await httpFn(lanEndpoints[i].url)
        TransferRouteLog.record('lan', true)
        preparation?.cancel()
        return
      } catch (e) {
        lastError = e as Error
        TransferRouteLog.record('lan', false)
      }
    }

    if (preparation !== null) {
      try {
        const channel = await FilesService.withTimeout(preparation.ready, P2pTransfer.READY_WAIT_MS,
          'P2P hole punching did not complete in time')
        try {
          await p2pFn(channel, relayToken)
          TransferRouteLog.record('p2p', true)
          preparation.cancel()
          return
        } finally {
          await channel.close()
        }
      } catch (e) {
        lastError = e as Error
        preparation.cancel()
        TransferRouteLog.record('p2p', false)
      }
    }

    for (let i = 0; i < restEndpoints.length; i++) {
      try {
        await httpFn(restEndpoints[i].url)
        TransferRouteLog.record(restEndpoints[i].kind.toLowerCase(), true)
        preparation?.cancel()
        return
      } catch (e) {
        lastError = e as Error
        TransferRouteLog.record(restEndpoints[i].kind.toLowerCase(), false)
      }
    }
    throw lastError
  }

  /** p2p 数据面下载：流式写目标文件（对齐 FileDownloader 的落盘位置语义）。 */
  private static async downloadOverP2p(channel: P2pChannel, transferId: string, relayToken: string,
    targetPath: string): Promise<void> {
    const finalPath = FileDownloader.resolveAvailablePath(targetPath)
    const file = fs.openSync(finalPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      await P2pTransfer.downloadP2p(channel, transferId, relayToken, (chunk: ArrayBuffer) => {
        fs.writeSync(file.fd, chunk)
      })
    } finally {
      fs.closeSync(file)
    }
  }

  /** RelayToken 在端点 URL 的 token query 里（LAN/公网/Relay 契约相同，取其一）。 */
  private static relayTokenFromEndpoints(endpoints: TransferEndpointModel[]): string {
    for (let i = 0; i < endpoints.length; i++) {
      const marker = 'token='
      const idx = endpoints[i].url.indexOf(marker)
      if (idx >= 0) {
        const rest = endpoints[i].url.substring(idx + marker.length)
        const amp = rest.indexOf('&')
        const raw = amp >= 0 ? rest.substring(0, amp) : rest
        return decodeURIComponent(raw)
      }
    }
    return ''
  }

  private static withTimeout<T>(promise: Promise<T>, timeoutMs: number, message: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const timerId = setTimeout(() => {
        reject(new Error(message))
      }, timeoutMs)
      promise.then((value: T) => {
        clearTimeout(timerId)
        resolve(value)
      }, (e: Object) => {
        clearTimeout(timerId)
        reject(e as Error)
      })
    })
  }
}
