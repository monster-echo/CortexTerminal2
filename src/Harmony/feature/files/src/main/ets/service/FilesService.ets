/**
 * @file FilesService.ets
 * @brief REST client for the remote-files flows.
 *
 * Pure REST + polling — no SignalR. Byte transfers go through Gateway-brokered
 * presigned S3 URLs (ApiService.putBinaryToS3 / FileDownloader); the Gateway never
 * relays file bytes.
 */
import { ApiService } from '@rwecho/core'
import { FileListingModel, DownloadPollState, UploadInitModel } from '../model/FileModels'

export class FilesService {
  /** List one directory of the session root ('' = root). */
  static async listFiles(sessionId: string, path: string): Promise<FileListingModel> {
    const response = await ApiService.listFiles(sessionId, path) as Record<string, Object>
    return FileListingModel.fromRecord(response)
  }

  /** Upload step 1: register the transfer and get a presigned PUT URL. */
  static async beginUpload(sessionId: string, dirPath: string, filename: string,
    sizeBytes: number, sha256: string): Promise<UploadInitModel> {
    const response = await ApiService.createFileUpload(sessionId, dirPath, filename, sizeBytes, sha256)
    const init = new UploadInitModel()
    init.requestId = (response['requestId'] as string) ?? ''
    init.uploadUrl = (response['uploadUrl'] as string) ?? ''
    return init
  }

  /** Upload step 3: ask the worker to mirror the uploaded object into the target dir. */
  static async completeUpload(sessionId: string, requestId: string): Promise<void> {
    await ApiService.completeFileUpload(sessionId, requestId)
  }

  /** Download step 1: validate the file on the worker and start the background push to S3. */
  static async startDownload(sessionId: string, path: string): Promise<string> {
    const response = await ApiService.startFileDownload(sessionId, path)
    return (response['requestId'] as string) ?? ''
  }

  /** Download step 2: poll until status is ready (downloadUrl set) or failed. */
  static async pollDownload(sessionId: string, requestId: string): Promise<DownloadPollState> {
    const response = await ApiService.pollFileDownload(sessionId, requestId)
    return DownloadPollState.fromRecord(response)
  }
}
