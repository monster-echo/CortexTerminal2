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

  static async uploadFromUri(context: Context, sessionId: string, fileUri: string, filename: string): Promise<void> {
    // Picker URIs (documents / media) carry only temporary authorization and
    // @ohos.file.hash rejects them. Copy into the sandbox first, then hash + read.
    const sandboxPath = `${context.cacheDir}/${Date.now()}_${filename}`
    const srcFile = fs.openSync(fileUri, fs.OpenMode.READ_ONLY)
    const destFile = fs.openSync(sandboxPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE)
    try {
      await fs.copyFile(srcFile.fd, destFile.fd)
    } finally {
      fs.closeSync(srcFile)
      fs.closeSync(destFile)
    }

    try {
      const sha256 = await hash.hash(sandboxPath, 'sha256')
      const stat = fs.statSync(sandboxPath)
      const sizeBytes = stat.size
      const readFile = fs.openSync(sandboxPath, fs.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(sizeBytes)
      try {
        fs.readSync(readFile.fd, buffer)
      } finally {
        fs.closeSync(readFile)
      }

      const createResp = await ApiService.createArtifactUpload(sessionId, filename, sizeBytes, sha256)
      const uploadUrl = (createResp['uploadUrl'] as string) ?? ''
      const artifactId = (createResp['artifactId'] as string) ?? ''

      await ApiService.putBinaryToS3(uploadUrl, buffer)
      await ApiService.completeArtifactUpload(sessionId, artifactId, sha256)
    } finally {
      fs.unlinkSync(sandboxPath)
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
