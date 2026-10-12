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
import { FileDownloader, ENDPOINT_STALL_MS, LAST_ENDPOINT_STALL_MS } from './FileDownloader'
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
   * 端点协商上传：p2p（worker 常驻锚点，6s 内打通才用）→ 公网 → Relay，
   * 任一端点成功即返回；全部失败抛出最后一次错误。
   */
  static async uploadViaEndpoints(workerId: string, transferId: string, endpoints: TransferEndpointModel[],
    buffer: ArrayBuffer): Promise<void> {
    await FilesService.transferViaEndpoints(workerId, transferId, endpoints, async (channel: P2pChannel, relayToken: string): Promise<string> => {
      await P2pTransfer.uploadP2p(channel, transferId, relayToken, buffer)
      return ''
    }, async (url: string, _stallMs: number): Promise<string> => {
      await ApiService.putBinary(url, buffer)
      return ''
    })
  }

  /**
   * 端点协商下载：p2p（worker 常驻锚点，6s 内打通才用）→ 公网 → Relay，逐个尝试
   * GET 下载到本地沙箱。LAN 直连已按产品决策移除（手机与 worker 不同网段时必然
   * 超时，只会拖慢协商）。
   */
  static async downloadViaEndpoints(context: Context, targetPath: string, transferId: string,
    endpoints: TransferEndpointModel[], workerId: string): Promise<string> {
    return await FilesService.transferViaEndpoints(workerId, transferId, endpoints,
      async (channel: P2pChannel, relayToken: string) => {
        return await FilesService.downloadOverP2p(channel, transferId, relayToken, targetPath)
      }, async (url: string, stallMs: number) => {
        return await FileDownloader.download(context, targetPath, url, stallMs)
      })
  }

  /**
   * 端点协商公共骨架：发起时并行启动 worker 锚点 p2p 准备（注册后首轮即拿 worker
   * 端点），先等 p2p（READY_WAIT_MS 内打通才用），未打通则按网关下发顺序逐个尝试
   * 其余端点（公网 → Relay）。p2p 失败静默落下一端点——这是规格允许的唯一回落。
   */
  private static async transferViaEndpoints(workerId: string, transferId: string,
    endpoints: TransferEndpointModel[],
    p2pFn: (channel: P2pChannel, relayToken: string) => Promise<string>,
    httpFn: (url: string, stallMs: number) => Promise<string>): Promise<string> {
    if (endpoints.length === 0) {
      throw new Error('no transfer endpoints')
    }
    const relayToken = FilesService.relayTokenFromEndpoints(endpoints)

    // p2p 与 HTTP 端点并行准备：worker 锚点常驻，注册响应即含 worker 端点
    let preparation: P2pPreparation | null = null
    if (workerId.length > 0 && relayToken.length > 0) {
      preparation = P2pTransfer.startPreparationForWorker(workerId, transferId, relayToken)
    }

    let lastError: Error = new Error('all transfer endpoints failed')
    if (preparation !== null) {
      try {
        const channel = await FilesService.withTimeout(preparation.ready, P2pTransfer.READY_WAIT_MS,
          'P2P hole punching did not complete in time')
        try {
          const localPath = await p2pFn(channel, relayToken)
          TransferRouteLog.record('p2p', true)
          preparation.cancel()
          return localPath
        } finally {
          await channel.close()
        }
      } catch (e) {
        lastError = e as Error
        preparation.cancel()
        TransferRouteLog.record('p2p', false)
      }
    }

    for (let i = 0; i < endpoints.length; i++) {
      // 防御旧网关：LAN 直连端点对手机网络必然不可达，跳过不让它消耗看门狗窗口。
      if (endpoints[i].kind.toLowerCase() === 'lan') {
        TransferRouteLog.record('lan', false)
        continue
      }
      // 最后一跳多等：它失败就意味着整个传输失败，且 relay 侧自己会等 worker 配对
      // 最长 90s——客户端的耐心必须 ≥ 服务端的等待，否则配对成功前先被掐死。
      const isLast = i === endpoints.length - 1
      const stallMs = isLast ? LAST_ENDPOINT_STALL_MS : ENDPOINT_STALL_MS
      try {
        const localPath = await httpFn(endpoints[i].url, stallMs)
        TransferRouteLog.record(endpoints[i].kind.toLowerCase(), true)
        preparation?.cancel()
        return localPath
      } catch (e) {
        lastError = e as Error
        TransferRouteLog.record(endpoints[i].kind.toLowerCase(), false)
      }
    }
    throw lastError
  }

  /** p2p 数据面下载：流式写目标文件（落盘位置语义与 FileDownloader 一致），返回实际路径。 */
  private static async downloadOverP2p(channel: P2pChannel, transferId: string, relayToken: string,
    targetPath: string): Promise<string> {
    const finalPath = FileDownloader.resolveAvailablePath(targetPath)
    const file = fs.openSync(finalPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      await P2pTransfer.downloadP2p(channel, transferId, relayToken, (chunk: ArrayBuffer) => {
        fs.writeSync(file.fd, chunk)
      })
    } finally {
      fs.closeSync(file)
    }
    return finalPath
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
