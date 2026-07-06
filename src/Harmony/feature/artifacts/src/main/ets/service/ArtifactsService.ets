/**
 * @file ArtifactsService.ets
 * @brief REST client wrapping ApiService for artifact feed operations.
 *
 * All S3 byte transfers go through Gateway-brokered presigned URLs via
 * ApiService.putBinaryToS3. Gateway never relays file bytes.
 */
import { ApiService } from '@rwecho/core'
import { ArtifactModel, mapArtifactModel, detectFileCategory, FileCategory } from '../model/ArtifactModels'
import fs from '@ohos.file.fs'
import hash from '@ohos.file.hash'

export class ArtifactsService {
  static async listArtifacts(sessionId: string): Promise<ArtifactModel[]> {
    const response = await ApiService.listArtifacts(sessionId)
    const records = response as Record<string, Object>[]
    const artifacts: ArtifactModel[] = []
    for (let i = 0; i < records.length; i++) {
      artifacts.push(mapArtifactModel(records[i]))
    }
    return artifacts
  }

  static async uploadFromUri(sessionId: string, fileUri: string, filename: string): Promise<void> {
    const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY)
    try {
      const stat = fs.statSync(file.fd)
      const sizeBytes = stat.size
      const buffer = new ArrayBuffer(sizeBytes)
      fs.readSync(file.fd, buffer)
      const sha256 = await hash.hash(fileUri, 'sha256')

      const createResp = await ApiService.createArtifactUpload(sessionId, filename, sizeBytes, sha256)
      const uploadUrl = (createResp['uploadUrl'] as string) ?? ''
      const artifactId = (createResp['artifactId'] as string) ?? ''

      await ApiService.putBinaryToS3(uploadUrl, buffer)
      await ApiService.completeArtifactUpload(sessionId, artifactId, sha256)
    } finally {
      fs.closeSync(file)
    }
  }

  static async getDownloadUrl(sessionId: string, artifactId: string): Promise<string> {
    return await ApiService.getArtifactDownloadUrl(sessionId, artifactId)
  }

  static async deleteArtifact(sessionId: string, artifactId: string): Promise<void> {
    await ApiService.deleteArtifact(sessionId, artifactId)
  }

  static detectCategory(filename: string): string {
    return detectFileCategory(filename)
  }

  static categoryUnknown(): string {
    return FileCategory.UNKNOWN
  }
}
