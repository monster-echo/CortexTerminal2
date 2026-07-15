import { useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Loader2, Paperclip, Upload } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { ScrollArea } from '@/components/ui/scroll-area'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { getApi } from '@/lib/api'
import { uploadArtifact, useInvalidateArtifacts } from './artifacts-api'
import { ArtifactBubble, type ArtifactActor } from './artifact-bubble'
import { useArtifacts } from './use-artifacts'
import { useCurrentUser } from './use-current-user'
import { useArtifactUnreadStore } from './use-artifact-unread-store'

export function ArtifactFeedSheet(props: { sessionId: string }) {
  const { sessionId } = props
  const { t } = useTranslation()
  const { artifacts, isLoading } = useArtifacts(sessionId)
  const fileInputRef = useRef<HTMLInputElement | null>(null)
  const invalidateArtifacts = useInvalidateArtifacts(sessionId)
  const me = useCurrentUser()
  const sessionQuery = useQuery({
    queryKey: ['sessions', sessionId],
    queryFn: () => getApi().getSession(sessionId),
  })
  const [open, setOpen] = useState(false)
  const lastSeenAt = useArtifactUnreadStore((s) => s.lastSeenAt[sessionId])
  const markSeen = useArtifactUnreadStore((s) => s.markSeen)

  const myActor: ArtifactActor = {
    displayName: me.data?.displayName || me.data?.username || t('terminal.artifacts.me'),
    avatarUrl: me.data?.avatarUrl,
  }
  const workerActor: ArtifactActor = {
    displayName:
      sessionQuery.data?.workerName ||
      sessionQuery.data?.workerHostname ||
      t('terminal.artifacts.worker'),
  }

  const hasUnread = useMemo(
    () =>
      artifacts.some(
        (a) =>
          a.origin === 'worker' &&
          (!lastSeenAt || new Date(a.uploadedAt) > new Date(lastSeenAt))
      ),
    [artifacts, lastSeenAt]
  )

  useEffect(() => {
    if (!open || artifacts.length === 0) return
    const latest = artifacts[artifacts.length - 1].uploadedAt
    markSeen(sessionId, latest)
  }, [open, artifacts, sessionId, markSeen])

  const uploadMutation = useMutation({
    mutationFn: async (file: File) => uploadArtifact(getApi(), sessionId, file, invalidateArtifacts),
    onSuccess: () => {
      toast.success(t('terminal.artifacts.uploadSuccess'))
    },
    onError: (err) => {
      toast.error((err as Error).message)
    },
  })

  const groups = useMemo(() => groupByDay(artifacts), [artifacts])

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button
          variant='outline'
          size='sm'
          className='relative'
          title={t('terminal.artifacts.button')}
        >
          <Paperclip className='size-4' />
          {hasUnread && (
            <span className='absolute right-1 top-1 size-2 rounded-full bg-destructive' />
          )}
        </Button>
      </SheetTrigger>
      <SheetContent side='right' className='flex w-full flex-col sm:max-w-lg'>
        <SheetHeader>
          <SheetTitle>{t('terminal.artifacts.title')}</SheetTitle>
          <SheetDescription>{t('terminal.artifacts.description')}</SheetDescription>
        </SheetHeader>

        <ScrollArea className='min-h-0 flex-1'>
          <div className='space-y-4 p-4'>
            {isLoading && artifacts.length === 0 && (
              <div className='flex items-center justify-center py-12 text-muted-foreground'>
                <Loader2 className='mr-2 size-4 animate-spin' />
                {t('common.loading')}
              </div>
            )}

            {!isLoading && artifacts.length === 0 && (
              <div className='py-12 text-center text-sm text-muted-foreground'>
                {t('terminal.artifacts.empty')}
              </div>
            )}

            {groups.map((group) => (
              <div key={group.key} className='space-y-3'>
                <div className='flex items-center gap-2 text-xs text-muted-foreground'>
                  <div className='h-px flex-1 bg-border' />
                  <span>{group.label}</span>
                  <div className='h-px flex-1 bg-border' />
                </div>
                {group.items.map((artifact) => (
                  <ArtifactBubble
                    key={artifact.id}
                    sessionId={sessionId}
                    artifact={artifact}
                    fromMe={artifact.origin === 'console'}
                    actor={artifact.origin === 'console' ? myActor : workerActor}
                  />
                ))}
              </div>
            ))}
          </div>
        </ScrollArea>

        <div className='border-t p-3'>
          <input
            ref={fileInputRef}
            type='file'
            className='hidden'
            onChange={(e) => {
              const file = e.target.files?.[0]
              if (file) {
                uploadMutation.mutate(file)
                e.target.value = ''
              }
            }}
          />
          <Button
            className='w-full'
            disabled={uploadMutation.isPending}
            onClick={() => fileInputRef.current?.click()}
          >
            {uploadMutation.isPending ? (
              <Loader2 className='mr-2 size-4 animate-spin' />
            ) : (
              <Upload className='mr-2 size-4' />
            )}
            {t('terminal.artifacts.upload')}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  )
}

interface DayGroup {
  key: string
  label: string
  items: Array<NonNullable<ReturnType<typeof useArtifacts>['artifacts'][number]>>
}

function groupByDay(artifacts: ReturnType<typeof useArtifacts>['artifacts']): DayGroup[] {
  const buckets = new Map<string, DayGroup>()
  for (const artifact of artifacts) {
    const date = new Date(artifact.uploadedAt)
    const key = formatDateKey(date)
    if (!buckets.has(key)) {
      buckets.set(key, { key, label: formatDayLabel(date), items: [] })
    }
    buckets.get(key)!.items.push(artifact)
  }
  return Array.from(buckets.values()).sort((a, b) => (a.key < b.key ? -1 : 1))
}

function formatDateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function formatDayLabel(date: Date): string {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const yesterday = new Date(today)
  yesterday.setDate(today.getDate() - 1)
  const target = new Date(date)
  target.setHours(0, 0, 0, 0)
  if (target.getTime() === today.getTime()) {
    return new Intl.DateTimeFormat().format(today) + ' · Today'
  }
  if (target.getTime() === yesterday.getTime()) {
    return new Intl.DateTimeFormat().format(yesterday) + ' · Yesterday'
  }
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(date)
}
