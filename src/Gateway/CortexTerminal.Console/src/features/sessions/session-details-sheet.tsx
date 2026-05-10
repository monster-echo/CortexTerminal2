import type { ReactNode } from 'react'
import { CircleAlert, Info } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import type { SessionDetail } from '@/services/console-api'
import { StatusBadge } from '@/components/shared/status-badge'
import { Badge } from '@/components/ui/badge'
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

export function SessionDetailsSheet(props: {
  session: SessionDetail
  latencyMs: number | null
  latencyState: 'live' | 'measuring' | 'offline'
}) {
  const { session, latencyMs, latencyState } = props
  const { t } = useTranslation()

  return (
    <Sheet>
      <SheetTrigger asChild>
        <Button variant='outline' size='sm'>
          <Info className='size-4' />
          {t('sessions.details.button')}
        </Button>
      </SheetTrigger>
      <SheetContent side='right' className='flex w-full flex-col sm:max-w-lg'>
        <SheetHeader>
          <SheetTitle>{t('sessions.details.title')}</SheetTitle>
          <SheetDescription>
            {t('sessions.details.description')}
          </SheetDescription>
        </SheetHeader>
        <ScrollArea className='min-h-0 flex-1'>
          <div className='space-y-6 p-4'>
            <DetailSection title={t('sessions.details.sections.session')}>
              <DetailRow
                label={t('sessions.details.labels.sessionId')}
                value={<code className='font-mono text-xs'>{session.sessionId}</code>}
              />
              <DetailRow
                label={t('sessions.details.labels.status')}
                value={
                  <StatusBadge
                    status={session.status}
                    label={t(`sessions.status.${session.status}`)}
                  />
                }
              />
              <DetailRow
                label={t('sessions.details.labels.e2eHealth')}
                value={
                  <Badge
                    variant={latencyState === 'offline' ? 'destructive' : 'outline'}
                    className={latencyState === 'live' ? 'border-emerald-500/30 bg-emerald-500/8 text-emerald-500' : undefined}
                  >
                    {formatLatencyLabel(t, latencyMs, latencyState)}
                  </Badge>
                }
              />
              <DetailRow
                label={t('sessions.details.labels.dimensions')}
                value={`${session.columns}x${session.rows}`}
              />
              <DetailRow
                label={t('sessions.details.labels.createdAt')}
                value={formatDateTime(session.createdAt)}
              />
              <DetailRow
                label={t('sessions.details.labels.lastActivityAt')}
                value={formatDateTime(session.lastActivityAt)}
              />
            </DetailSection>

            <DetailSection title={t('sessions.details.sections.transport')}>
              <DetailRow
                label={t('sessions.details.labels.attachmentState')}
                value={session.attachmentState}
              />
              <DetailRow
                label={t('sessions.details.labels.attachedClient')}
                value={session.attachedClientConnectionId ?? '\u2014'}
                monospaced
              />
              <DetailRow
                label={t('sessions.details.labels.replayPending')}
                value={session.replayPending ? t('sessions.details.values.yes') : t('sessions.details.values.no')}
              />
              <DetailRow
                label={t('sessions.details.labels.leaseExpiresAt')}
                value={formatNullableDateTime(session.leaseExpiresAt)}
              />
            </DetailSection>

            <DetailSection title={t('sessions.details.sections.worker')}>
              <DetailRow
                label={t('sessions.details.labels.workerId')}
                value={<code className='font-mono text-xs'>{session.workerId}</code>}
              />
              <DetailRow
                label={t('sessions.details.labels.workerOnline')}
                value={
                  <StatusBadge
                    status={session.workerOnline ? 'online' : 'offline'}
                    label={session.workerOnline ? t('workers.status.online') : t('workers.status.offline')}
                  />
                }
              />
              <DetailRow
                label={t('sessions.details.labels.routeBinding')}
                value={<RouteBindingBadge bindingStatus={session.workerConnectionStatus} />}
              />
              {(session.workerConnectionStatus === 'stale') && (
                <div className='flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-700 dark:text-amber-200'>
                  <CircleAlert className='mt-0.5 size-4 shrink-0 text-amber-500' />
                  <span>{t('sessions.details.bindingWarning')}</span>
                </div>
              )}
              <DetailRow
                label={t('sessions.details.labels.workerName')}
                value={session.workerName ?? '\u2014'}
              />
              <DetailRow
                label={t('sessions.details.labels.workerHost')}
                value={session.workerHostname ?? '\u2014'}
              />
              <DetailRow
                label={t('sessions.details.labels.workerOs')}
                value={formatWorkerPlatform(session)}
              />
              <DetailRow
                label={t('sessions.details.labels.workerVersion')}
                value={session.workerVersion ?? '\u2014'}
              />
              <DetailRow
                label={t('sessions.details.labels.workerLastSeenAt')}
                value={formatNullableDateTime(session.workerLastSeenAt)}
              />
              <DetailRow
                label={t('sessions.details.labels.sessionWorkerConnection')}
                value={session.sessionWorkerConnectionId}
                monospaced
              />
              <DetailRow
                label={t('sessions.details.labels.currentWorkerConnection')}
                value={session.currentWorkerConnectionId ?? '\u2014'}
                monospaced
              />
            </DetailSection>

            <DetailSection title={t('sessions.details.sections.lifecycle')}>
              <DetailRow
                label={t('sessions.details.labels.exitCode')}
                value={session.exitCode === null ? '\u2014' : String(session.exitCode)}
              />
              <DetailRow
                label={t('sessions.details.labels.exitReason')}
                value={session.exitReason ?? '\u2014'}
              />
            </DetailSection>
          </div>
        </ScrollArea>
      </SheetContent>
    </Sheet>
  )
}

function DetailSection(props: { title: string; children: ReactNode }) {
  const { title, children } = props

  return (
    <section className='space-y-3'>
      <h3 className='text-sm font-semibold tracking-wide text-muted-foreground uppercase'>
        {title}
      </h3>
      <div className='space-y-3 rounded-lg border bg-card p-4'>{children}</div>
    </section>
  )
}

function DetailRow(props: {
  label: string
  value: ReactNode
  monospaced?: boolean
}) {
  const { label, value, monospaced = false } = props

  return (
    <div className='grid grid-cols-[minmax(0,140px)_1fr] gap-3 text-sm'>
      <dt className='text-muted-foreground'>{label}</dt>
      <dd className={monospaced ? 'min-w-0 break-all font-mono text-xs' : 'min-w-0 break-words'}>
        {value}
      </dd>
    </div>
  )
}

function RouteBindingBadge(props: {
  bindingStatus: SessionDetail['workerConnectionStatus']
}) {
  const { bindingStatus } = props
  const { t } = useTranslation()

  if (bindingStatus === 'matched') {
    return (
      <Badge className='border-emerald-500/30 bg-emerald-500/10 text-emerald-500'>
        {t('sessions.details.connectionStatus.matched')}
      </Badge>
    )
  }

  if (bindingStatus === 'stale') {
    return <Badge variant='destructive'>{t('sessions.details.connectionStatus.stale')}</Badge>
  }

  return <Badge variant='secondary'>{t('sessions.details.connectionStatus.offline')}</Badge>
}

function formatLatencyLabel(
  t: ReturnType<typeof useTranslation>['t'],
  latencyMs: number | null,
  latencyState: 'live' | 'measuring' | 'offline'
) {
  if (latencyState === 'offline') {
    return t('terminal.offline')
  }

  if (latencyMs === null) {
    return t('terminal.measuring')
  }

  return t('terminal.latency', { ms: Math.round(latencyMs) })
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function formatNullableDateTime(value: string | null) {
  return value ? formatDateTime(value) : '\u2014'
}

function formatWorkerPlatform(session: SessionDetail) {
  const parts = [session.workerOperatingSystem, session.workerArchitecture].filter(Boolean)
  return parts.length > 0 ? parts.join(' · ') : '\u2014'
}
