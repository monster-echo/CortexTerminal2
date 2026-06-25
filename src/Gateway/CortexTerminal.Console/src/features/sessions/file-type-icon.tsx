import {
  File as FileIcon,
  FileArchive,
  FileAudio,
  FileCode,
  FileImage,
  FileText,
  FileVideo,
  HelpCircle,
} from 'lucide-react'
import type { ArtifactFileCategory } from '@/services/console-api'

const ICON_MAP: Record<ArtifactFileCategory, typeof FileIcon> = {
  image: FileImage,
  pdf: FileText,
  video: FileVideo,
  audio: FileAudio,
  archive: FileArchive,
  code: FileCode,
  text: FileText,
  unknown: HelpCircle,
}

const COLOR_MAP: Record<ArtifactFileCategory, string> = {
  image: 'text-pink-500',
  pdf: 'text-red-500',
  video: 'text-purple-500',
  audio: 'text-amber-500',
  archive: 'text-orange-500',
  code: 'text-blue-500',
  text: 'text-emerald-500',
  unknown: 'text-muted-foreground',
}

export function FileTypeIcon(props: {
  category: ArtifactFileCategory
  size?: number
}) {
  const { category, size = 24 } = props
  const Icon = ICON_MAP[category] ?? FileIcon
  const color = COLOR_MAP[category]
  return <Icon className={color} style={{ width: size, height: size }} />
}
