/**
 * @file FilesService.ets
 * @brief REST client for the workspace-scoped remote file flows (v2).
 *
 * Pure REST — no SignalR, no polling. Browsing is a live worker RPC via the Gateway;
 * upload/download get a signed transfer id plus candidate endpoints from the Gateway,
 * then stream bytes directly against the Relay (or a direct endpoint when present).
 */
import { ApiService } from '@rwecho/core'
import { FileDownloader } from './FileDownloader'
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
   * 端点协商上传：按优先序（LAN 直连 → 公网直连 → Relay 兜底）逐个尝试 PUT，
   * 任一端点成功即返回；全部失败抛出最后一次错误。
   */
  static async uploadViaEndpoints(endpoints: TransferEndpointModel[], buffer: ArrayBuffer): Promise<void> {
    let lastError = new Error('no transfer endpoints')
    for (let i = 0; i < endpoints.length; i++) {
      try {
        await ApiService.putBinary(endpoints[i].url, buffer)
        return
      } catch (e) {
        lastError = e as Error
      }
    }
    throw lastError
  }

  /**
   * 端点协商下载：按优先序逐个尝试 GET 下载到本地沙箱，任一端点成功即返回。
   */
  static async downloadViaEndpoints(context: Context, targetPath: string,
    endpoints: TransferEndpointModel[]): Promise<void> {
    let lastError = new Error('no transfer endpoints')
    for (let i = 0; i < endpoints.length; i++) {
      try {
        await FileDownloader.download(context, targetPath, endpoints[i].url)
        return
      } catch (e) {
        lastError = e as Error
      }
    }
    throw lastError
  }
}
