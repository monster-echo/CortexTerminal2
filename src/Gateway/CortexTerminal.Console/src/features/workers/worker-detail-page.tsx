import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Link, useNavigate, useParams } from '@tanstack/react-router'
import { type SessionStatus } from '@/services/console-api'
import { formatDistanceToNow } from 'date-fns'
import { ArrowLeft, Loader2 } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { StatusDot } from '@/components/shared/status-dot'
import { StatusBadge } from '@/components/shared/status-badge'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { getApi } from '@/lib/api'

export function WorkerDetailPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { workerId } = useParams({ strict: false }) as { workerId: string }
  const api = getApi()

  const workerQuery = useQuery({
    queryKey: ['workers', workerId],
    queryFn: () => api.getWorker(workerId),
  })

  const worker = workerQuery.data

  if (workerQuery.isLoading) {
    return (
      <>
        <Header>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/workers'>
              <ArrowLeft /> {t('workers.backToWorkers', 'Back to workers')}
            </Link>
          </Button>
        </Header>
        <Main>
          <div className='flex items-center gap-2 text-sm text-muted-foreground'>
            <Loader2 className='size-4 animate-spin' /> {t('common.loading')}
          </div>
        </Main>
      </>
    )
  }

  if (workerQuery.isError || !worker) {
    return (
      <>
        <Header>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/workers'>
              <ArrowLeft /> {t('workers.backToWorkers', 'Back to workers')}
            </Link>
          </Button>
        </Header>
        <Main>
          <Card>
            <CardHeader>
              <CardTitle>
                {t('workers.loadError', 'Could not load worker')}
              </CardTitle>
            </CardHeader>
            <CardContent className='space-y-4'>
              <p className='text-sm text-destructive'>
                {workerQuery.error instanceof Error
                  ? workerQuery.error.message
                  : t('common.error')}
              </p>
              <Button
                variant='outline'
                onClick={() => navigate({ to: '/workers' })}
              >
                {t('workers.backToWorkers', 'Return to workers')}
              </Button>
            </CardContent>
          </Card>
        </Main>
      </>
    )
  }

  const status = worker.isOnline ? 'online' : 'offline'
  const statusLabel = worker.isOnline
    ? t('workers.status.online')
    : t('workers.status.offline')

  return (
    <>
      <Header>
        <Button variant='ghost' size='sm' asChild>
          <Link to='/workers'>
            <ArrowLeft /> {t('workers.backToWorkers', 'Back to workers')}
          </Link>
        </Button>
      </Header>

      <Main>
        <div className='mb-6'>
          <h2 className='text-2xl font-bold tracking-tight'>
            {worker.name ?? worker.workerId}
          </h2>
          <p className='text-muted-foreground'>
            {t('workers.detailSubtitle', 'Worker details and sessions')}
          </p>
        </div>

        <Card className='mb-6'>
          <CardHeader>
            <CardTitle className='flex items-center gap-3'>
              <StatusDot status={status} />
              <span className='font-mono text-base'>{worker.workerId}</span>
              <StatusBadge status={status} label={statusLabel} />
            </CardTitle>
          </CardHeader>
          <CardContent>
            <dl className='grid grid-cols-1 gap-4 sm:grid-cols-3'>
              <div>
                <dt className='text-sm font-medium text-muted-foreground'>
                  {t('workers.address')}
                </dt>
                <dd className='mt-1 font-mono text-sm'>
                  {worker.address ?? '\u2014'}
                </dd>
              </div>
              <div>
                <dt className='text-sm font-medium text-muted-foreground'>
                  {t('workers.connectedAt', 'Connected')}
                </dt>
                <dd className='mt-1 text-sm'>
                  {worker.connectedAt
                    ? new Intl.DateTimeFormat(undefined, {
                        dateStyle: 'medium',
                        timeStyle: 'short',
                      }).format(new Date(worker.connectedAt))
                    : '\u2014'}
                </dd>
              </div>
              <div>
                <dt className='text-sm font-medium text-muted-foreground'>
                  {t('workers.uptime')}
                </dt>
                <dd className='mt-1 text-sm'>
                  {worker.connectedAt
                    ? formatDistanceToNow(new Date(worker.connectedAt), {
                        addSuffix: true,
                      })
                    : '\u2014'}
                </dd>
              </div>
            </dl>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>
              {t('workers.sessionsTitle', 'Sessions on this Worker')}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {worker.sessions.length === 0 ? (
              <p className='text-sm text-muted-foreground'>
                {t('workers.noSessions', 'No sessions running on this worker.')}
              </p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>
                      {t('workers.sessionId', 'Session ID')}
                    </TableHead>
                    <TableHead>
                      {t('workers.status._label', 'Status')}
                    </TableHead>
                    <TableHead>
                      {t('workers.created', 'Created')}
                    </TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {worker.sessions.map((session) => (
                    <TableRow
                      key={session.sessionId}
                      className='cursor-pointer'
                      onClick={() =>
                        navigate({
                          to: '/sessions/$sessionId',
                          params: { sessionId: session.sessionId },
                        })
                      }
                    >
                      <TableCell className='font-mono text-xs sm:text-sm'>
                        {session.sessionId}
                      </TableCell>
                      <TableCell>
                        <SessionStatusBadge status={session.status} />
                      </TableCell>
                      <TableCell>
                        {formatDateTime(session.createdAt)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </Main>
    </>
  )
}

function SessionStatusBadge({ status }: { status: SessionStatus }) {
  const variant =
    status === 'live'
      ? 'default'
      : status === 'detached'
        ? 'secondary'
        : 'outline'

  return <Badge variant={variant}>{status}</Badge>
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}
