/**
 * @file FeedbackFilePicker.ets
 * @brief Generic file picker for feedback attachments (images, PDF, video, docs).
 *
 * Uses DocumentViewPicker (any file type) instead of photoAccessHelper so users
 * can attach PDFs, videos, documents, archives — not just photos. Reads the
 * picked file into an ArrayBuffer for direct S3 PUT (no base64 round-trip).
 */
import picker from '@ohos.file.picker'
import fs from '@ohos.file.fs'

const MAX_FILE_BYTES: number = 50 * 1024 * 1024 // 50 MB

export interface PickedFile {
  bytes: ArrayBuffer
  filename: string
  contentType: string
}

const CONTENT_TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.bmp': 'image/bmp',
  '.pdf': 'application/pdf',
  '.mp4': 'video/mp4',
  '.mov': 'video/quicktime',
  '.m4v': 'video/x-m4v',
  '.webm': 'video/webm',
  '.doc': 'application/msword',
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls': 'application/vnd.ms-excel',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt': 'application/vnd.ms-powerpoint',
  '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.csv': 'text/csv',
  '.zip': 'application/zip'
}

export class FeedbackFilePicker {
  static async pick(): Promise<PickedFile | null> {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 1
    const docPicker = new picker.DocumentViewPicker()
    const uris = await docPicker.select(options)
    if (uris.length === 0) {
      return null
    }
    const uri = uris[0]
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    try {
      const stat = fs.statSync(file.fd)
      const size = stat.size
      if (size > MAX_FILE_BYTES) {
        throw new Error(`文件不能超过 50MB`)
      }
      const buffer: ArrayBuffer = new ArrayBuffer(size)
      fs.readSync(file.fd, buffer)
      const filename = FeedbackFilePicker.extractFilename(uri)
      const dot = filename.lastIndexOf('.')
      const ext = dot >= 0 ? filename.substring(dot).toLowerCase() : ''
      const contentType = CONTENT_TYPES[ext] || 'application/octet-stream'
      return { bytes: buffer, filename, contentType }
    } finally {
      fs.closeSync(file)
    }
  }

  private static extractFilename(uri: string): string {
    let decoded = uri
    try {
      decoded = decodeURIComponent(uri)
    } catch (_e) {
      decoded = uri
    }
    const slash = decoded.lastIndexOf('/')
    const name = slash >= 0 ? decoded.substring(slash + 1) : decoded
    return name.length > 0 ? name : 'file'
  }
}
