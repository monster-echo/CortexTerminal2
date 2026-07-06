/**
 * @file ArtifactModels.ets
 * @brief Models for the artifact feed.
 *
 * ArkTS strict typing rules (see project CLAUDE.md):
 *   - Use `class X { static readonly A: string = 'a' }` instead of `as const`
 *   - DTO extraction: `(record['field'] as string) ?? ''`
 *   - Object literals need explicit `Record<string, Object>` typing
 */

export class FileCategory {
  static readonly IMAGE: string = 'image'
  static readonly PDF: string = 'pdf'
  static readonly VIDEO: string = 'video'
  static readonly AUDIO: string = 'audio'
  static readonly ARCHIVE: string = 'archive'
  static readonly CODE: string = 'code'
  static readonly TEXT: string = 'text'
  static readonly UNKNOWN: string = 'unknown'
}

export class ArtifactOrigin {
  static readonly CONSOLE: string = 'console'
  static readonly WORKER: string = 'worker'
}

export class ArtifactStatus {
  static readonly PENDING: string = 'pending'
  static readonly READY: string = 'ready'
  static readonly DELETED: string = 'deleted'
}

@Observed
export class ArtifactModel {
  id: string = ''
  sessionId: string = ''
  filename: string = ''
  sizeBytes: number = 0
  status: string = ArtifactStatus.PENDING
  origin: string = ArtifactOrigin.CONSOLE
  fileCategory: string = FileCategory.UNKNOWN
  uploadedAt: number = 0
  expiresAt: number = 0

  constructor(id: string, sessionId: string, filename: string, sizeBytes: number,
    status: string, origin: string, fileCategory: string,
    uploadedAt: number, expiresAt: number) {
    this.id = id
    this.sessionId = sessionId
    this.filename = filename
    this.sizeBytes = sizeBytes
    this.status = status
    this.origin = origin
    this.fileCategory = fileCategory
    this.uploadedAt = uploadedAt
    this.expiresAt = expiresAt
  }
}

const IMAGE_EXTS: Set<string> = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg', '.ico', '.tiff', '.tif', '.heic'
])
const PDF_EXTS: Set<string> = new Set(['.pdf'])
const VIDEO_EXTS: Set<string> = new Set([
  '.mp4', '.mov', '.mkv', '.webm', '.avi', '.flv', '.wmv', '.m4v', '.3gp'
])
const AUDIO_EXTS: Set<string> = new Set([
  '.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus'
])
const ARCHIVE_EXTS: Set<string> = new Set([
  '.zip', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.7z', '.rar', '.zst'
])
const CODE_EXTS: Set<string> = new Set([
  '.cs', '.ts', '.tsx', '.js', '.jsx', '.py', '.go', '.rs', '.java', '.kt', '.swift',
  '.c', '.cpp', '.cc', '.h', '.hpp', '.rb', '.php', '.scala', '.lua', '.pl',
  '.sh', '.bash', '.zsh', '.fish', '.ps1', '.bat', '.cmd',
  '.sql', '.vue', '.svelte', '.html', '.css', '.scss', '.sass', '.less',
  '.json', '.yaml', '.yml', '.toml', '.xml', '.ini', '.conf', '.env'
])
const TEXT_EXTS: Set<string> = new Set(['.txt', '.md', '.markdown', '.rst', '.log', '.csv', '.tsv', '.rtf'])

export function detectFileCategory(filename: string): string {
  const lower = filename.toLowerCase()
  const dotIdx = lower.lastIndexOf('.')
  if (dotIdx < 0 || dotIdx === lower.length - 1) {
    return FileCategory.UNKNOWN
  }
  const ext = lower.substring(dotIdx)
  if (IMAGE_EXTS.has(ext)) return FileCategory.IMAGE
  if (PDF_EXTS.has(ext)) return FileCategory.PDF
  if (VIDEO_EXTS.has(ext)) return FileCategory.VIDEO
  if (AUDIO_EXTS.has(ext)) return FileCategory.AUDIO
  if (ARCHIVE_EXTS.has(ext)) return FileCategory.ARCHIVE
  if (CODE_EXTS.has(ext)) return FileCategory.CODE
  if (TEXT_EXTS.has(ext)) return FileCategory.TEXT
  return FileCategory.UNKNOWN
}

export function mapArtifactModel(record: Record<string, Object>): ArtifactModel {
  const id = (record['id'] as string) ?? ''
  const sessionId = (record['sessionId'] as string) ?? ''
  const filename = (record['filename'] as string) ?? ''
  const sizeBytes = (record['sizeBytes'] as number) ?? 0
  const status = (record['status'] as string) ?? ArtifactStatus.PENDING
  const origin = (record['origin'] as string) ?? ArtifactOrigin.CONSOLE
  const fileCategory = (record['fileCategory'] as string) ?? detectFileCategory(filename)
  const uploadedAtStr = (record['uploadedAt'] as string) ?? ''
  const expiresAtStr = (record['expiresAt'] as string) ?? ''
  const uploadedAt = uploadedAtStr.length > 0 ? Date.parse(uploadedAtStr) : 0
  const expiresAt = expiresAtStr.length > 0 ? Date.parse(expiresAtStr) : 0
  return new ArtifactModel(id, sessionId, filename, sizeBytes, status, origin, fileCategory,
    uploadedAt, expiresAt)
}
