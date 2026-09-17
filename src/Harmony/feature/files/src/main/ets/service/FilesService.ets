/**
 * @file FilesService.ets
 * @brief REST client for the workspace-scoped remote file flows (v2).
 *
 * Pure REST — no SignalR, no polling. Browsing is a live worker RPC via the Gateway;
 * upload/download get a signed transfer id plus candidate endpoints from the Gateway,
 * then stream bytes directly against the Relay (or a direct endpoint when present).
 */
import { ApiService } from '@rwecho/core'
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

  /** List one directory of the workspace ('' = workspace root). */
  static async listFiles(workspaceId: string, path: string): Promise<FileListingModel> {
    const response = await ApiService.listFiles(workspaceId, path) as Record<string, Object>
    return FileListingModel.fromRecord(response)
  }

  /** Upload step 1: register the transfer, get candidate endpoints. */
  static async beginUpload(workspaceId: string, dirPath: string, filename: string,
    sizeBytes: number, sha256: string): Promise<UploadInitModel> {
    const response = await ApiService.createFileUpload(workspaceId, dirPath, filename, sizeBytes, sha256)
    const model = new UploadInitModel()
    model.transferId = (response['transferId'] as string) ?? ''
    FilesService.readEndpoints(response, model.endpoints)
    return model
  }

  /** Download step 1: validate on the worker, get candidate endpoints. */
  static async startDownload(workspaceId: string, path: string): Promise<DownloadInitModel> {
    const response = await ApiService.startFileDownload(workspaceId, path)
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
}
