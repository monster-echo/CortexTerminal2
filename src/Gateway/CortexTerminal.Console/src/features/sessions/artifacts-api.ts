import { useQueryClient } from '@tanstack/react-query'
import type { ConsoleApi } from '@/services/console-api'

export function useInvalidateArtifacts(sessionId: string) {
  const queryClient = useQueryClient()
  return () => queryClient.invalidateQueries({ queryKey: ['artifacts', sessionId] })
}

export async function uploadArtifact(
  api: ConsoleApi,
  sessionId: string,
  file: File,
  onSettled?: () => void
): Promise<void> {
  try {
    const upload = await api.createArtifactUpload(sessionId, file.name, file.size)
    await api.uploadArtifactToS3(upload.uploadUrl, file)
    await api.completeArtifactUpload(sessionId, upload.artifactId, '')
  } finally {
    onSettled?.()
  }
}

export async function downloadArtifact(
  api: ConsoleApi,
  sessionId: string,
  artifactId: string,
  filename: string
): Promise<void> {
  const { downloadUrl } = await api.getArtifactDownloadUrl(sessionId, artifactId)
  const resp = await fetch(downloadUrl)
  if (!resp.ok) {
    throw new Error(`Download failed: ${resp.status}`)
  }
  const blob = await resp.blob()
  const objectUrl = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = objectUrl
  link.download = filename.includes('%') ? decodeURIComponent(filename) : filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(objectUrl)
}
