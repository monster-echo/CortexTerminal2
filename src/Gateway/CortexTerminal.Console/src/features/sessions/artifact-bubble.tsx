import { Download, Loader2 } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { downloadArtifact } from './artifacts-api'
import { FileTypeIcon } from './file-type-icon'
import { getApi } from '@/lib/api'
import { useState } from 'react'

export interface ArtifactActor {
  displayName: string
  avatarUrl?: string | null
}

export function ArtifactBubble(props: {
  sessionId: string
  artifact: import('@/services/console-api').ArtifactInfo
  fromMe: boolean
  actor: ArtifactActor
}) {
  const { sessionId, artifact, fromMe, actor } = props
  const { t } = useTranslation()
  const [isDownloading, setIsDownloading] = useState(false)

  const handleDownload = async () => {
    setIsDownloading(true)
    toast.info(t('terminal.artifacts.downloading'))
    try {
      await downloadArtifact(getApi(), sessionId, artifact.id, artifact.filename)
    } catch (err) {
      toast.error((err as Error).message)
    } finally {
      setIsDownloading(false)
    }
  }

  const initials = actor.displayName.slice(0, 2).toUpperCase()

  return (
    <div className={`flex w-full gap-2 ${fromMe ? 'flex-row-reverse' : 'flex-row'}`}>
      <Avatar className='size-9 shrink-0 self-end'>
        {actor.avatarUrl && <AvatarImage src={actor.avatarUrl} alt={actor.displayName} />}
        <AvatarFallback className='text-xs'>{initials}</AvatarFallback>
      </Avatar>

      <div className={`flex max-w-[75%] flex-col gap-1 ${fromMe ? 'items-end' : 'items-start'}`}>
        <span className='px-1 text-xs text-muted-foreground'>{actor.displayName}</span>
        <div
          className={
            'flex flex-col gap-2 rounded-2xl border p-3 shadow-sm ' +
            (fromMe
              ? 'rounded-br-sm bg-secondary text-secondary-foreground'
              : 'rounded-bl-sm bg-card')
          }
        >
          <div className='flex items-start gap-3'>
            <FileTypeIcon category={artifact.fileCategory} />
            <div className='min-w-0 flex-1'>
              <p className='truncate font-medium'>{artifact.filename}</p>
              <p className='text-xs text-muted-foreground'>
                {formatBytes(artifact.sizeBytes)} · {formatTime(artifact.uploadedAt)}
              </p>
            </div>
          </div>
        </div>
      </div>

      {!fromMe && (
        <Button
          size='sm'
          variant='ghost'
          className='size-8 self-end p-0'
          onClick={handleDownload}
          disabled={isDownloading || artifact.status !== 'ready'}
          title={t('terminal.artifacts.download')}
        >
          {isDownloading || artifact.status !== 'ready' ? (
            <Loader2 className='size-4 animate-spin' />
          ) : (
            <Download className='size-4' />
          )}
        </Button>
      )}
    </div>
  )
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`
}

function formatTime(iso: string): string {
  return new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso))
}
