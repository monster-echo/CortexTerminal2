import { useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { useNavigate } from '@tanstack/react-router'
import { type SessionStatus } from '@/services/console-api'
import {
  Activity,
  Loader2,
  MonitorSmartphone,
  Plus,
  Server,
  ArrowRight,
} from 'lucide-react'
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
import { StatusBadge } from '@/components/shared/status-badge'
import { StatusDot } from '@/components/shared/status-dot'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { NewSessionDialog } from '@/components/new-session-dialog'
import { useWorkers } from '@/hooks/use-workers'
import { useSessions } from '@/hooks/use-sessions'

const statusBadgeLabel: Record<SessionStatus, string> = {
  live: 'Live',
  detached: 'Detached',
  expired: 'Expired',
  exited: 'Exited',
}

const sessionStatusToBadge: Record<SessionStatus, SessionStatus | 'online' | 'offline'> = {
  live: 'live',
  detached: 'detached',
  expired: 'expired',
  exited: 'exited',
}

export function Dashboard() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const [newSessionDialogOpen, setNewSessionDialogOpen] = useState(false)
  const [isCreatingSession, setIsCreatingSession] = useState(false)

  const workersQuery = useWorkers()
  const sessionsQuery = useSessions()

  const workers = workersQuery.data ?? []
  const sessions = sessionsQuery.data ?? []

  // Compute stats from actual data sources
  const activeSessions = sessions.filter((s) => s.status === 'live').length
  const detachedSessions = sessions.filter((s) => s.status === 'detached').length
  const onlineWorkers = workers.filter((w) => w.isOnline).length
  const recentSessions = sessions.slice(0, 5)

  // Worker info comes directly from the workers API
  const workerInfoMap = workers

  const handleCreateSession = useCallback((workerId?: string) => {
    const bootstrapId = crypto.randomUUID()
    setIsCreatingSession(true)
    setNewSessionDialogOpen(false)
    navigate({
      to: '/sessions/new',
      search: {
        bootstrapId,
        workerId,
      },
    })
  }, [navigate])

  return (
    <>
      <Header>
        <div>
          <p className='text-sm font-medium text-muted-foreground'>
            {t('brand.name')}
          </p>
          <h1 className='text-lg font-semibold'>{t('dashboard.title')}</h1>
        </div>
      </Header>

      <Main>
        {/* Stat Cards */}
        <div className='grid gap-4 sm:grid-cols-2 lg:grid-cols-4'>
          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>
                {t('dashboard.activeSessions')}
              </CardTitle>
              <MonitorSmartphone className='h-4 w-4 text-emerald-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{activeSessions}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>
                {t('dashboard.detachedSessions')}
              </CardTitle>
              <Activity className='h-4 w-4 text-amber-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{detachedSessions}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>
                {t('dashboard.onlineWorkers')}
              </CardTitle>
              <Server className='h-4 w-4 text-emerald-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{onlineWorkers}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>
                {t('dashboard.systemUptime')}
              </CardTitle>
              <Activity className='h-4 w-4 text-blue-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{t('dashboard.na')}</div>
            </CardContent>
          </Card>
        </div>

        {/* Bottom Section */}
        <div className='mt-6 grid gap-6 lg:grid-cols-7'>
          {/* Recent Sessions */}
          <Card className='col-span-1 lg:col-span-4'>
            <CardHeader className='flex flex-row items-center justify-between'>
              <CardTitle>{t('dashboard.recentSessions')}</CardTitle>
              <Button
                size='sm'
                onClick={() => setNewSessionDialogOpen(true)}
                disabled={isCreatingSession}
              >
                <Plus className='mr-1 h-4 w-4' />
                {t('dashboard.newSession')}
              </Button>
            </CardHeader>
            <CardContent>
              {sessionsQuery.isLoading ? (
                <div className='flex items-center gap-2 text-sm text-muted-foreground'>
                  <Loader2 className='size-4 animate-spin' />{' '}
                  {t('common.loading')}
                </div>
              ) : sessionsQuery.isError ? (
                <p className='text-sm text-destructive'>
                  {sessionsQuery.error instanceof Error
                    ? sessionsQuery.error.message
                    : t('common.error')}
                </p>
              ) : recentSessions.length === 0 ? (
                <div className='flex flex-col items-center justify-center rounded-lg border border-dashed p-8 text-center'>
                  <MonitorSmartphone className='mb-3 h-8 w-8 text-muted-foreground' />
                  <h3 className='text-lg font-semibold'>
                    {t('dashboard.noSessions')}
                  </h3>
                  <p className='mt-1 text-sm text-muted-foreground'>
                    {t('dashboard.noSessionsDescription')}
                  </p>
                </div>
              ) : (
                <>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>{t('dashboard.session')}</TableHead>
                        <TableHead>{t('dashboard.worker')}</TableHead>
                        <TableHead>{t('dashboard.status')}</TableHead>
                        <TableHead>{t('dashboard.created')}</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {recentSessions.map((session) => (
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
                          <TableCell className='font-mono text-xs'>
                            {truncateId(session.sessionId)}
                          </TableCell>
                          <TableCell className='font-mono text-xs'>
                            {truncateId(session.workerId)}
                          </TableCell>
                          <TableCell>
                            <StatusBadge
                              status={sessionStatusToBadge[session.status]}
                              label={statusBadgeLabel[session.status]}
                            />
                          </TableCell>
                          <TableCell className='text-xs text-muted-foreground'>
                            {formatDateTime(session.createdAt)}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  <div className='mt-4 flex justify-end'>
                    <Button
                      variant='ghost'
                      size='sm'
                      className='text-muted-foreground'
                      onClick={() => navigate({ to: '/sessions' })}
                    >
                      {t('dashboard.viewAll')}
                      <ArrowRight className='ml-1 h-4 w-4' />
                    </Button>
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          {/* Worker Status */}
          <Card className='col-span-1 lg:col-span-3'>
            <CardHeader>
              <CardTitle>{t('dashboard.workerStatus')}</CardTitle>
            </CardHeader>
            <CardContent>
              {workerInfoMap.length === 0 ? (
                <div className='flex flex-col items-center justify-center rounded-lg border border-dashed p-8 text-center'>
                  <Server className='mb-3 h-8 w-8 text-muted-foreground' />
                  <h3 className='text-lg font-semibold'>
                    {t('dashboard.noWorkers')}
                  </h3>
                  <p className='mt-1 text-sm text-muted-foreground'>
                    {t('dashboard.noWorkersDescription')}
                  </p>
                </div>
              ) : (
                <div className='grid gap-3'>
                  {workerInfoMap.map((worker) => {
                    const status = worker.isOnline ? 'online' as const : 'offline' as const
                    return (
                      <div
                        key={worker.workerId}
                        className='flex items-center justify-between rounded-lg border p-3'
                      >
                        <div className='flex items-center gap-3'>
                          <StatusDot status={status} />
                          <div>
                            <p className='font-mono text-sm'>
                              {truncateId(worker.workerId)}
                            </p>
                            <p className='text-xs text-muted-foreground'>
                              {worker.sessionCount}{' '}
                              {worker.sessionCount === 1
                                ? t('dashboard.session').toLowerCase()
                                : t('dashboard.recentSessions').toLowerCase()}
                            </p>
                          </div>
                        </div>
                        <StatusBadge
                          status={status}
                          label={status === 'online' ? 'Online' : 'Offline'}
                        />
                      </div>
                    )
                  })}
                  <div className='mt-2 flex justify-end'>
                    <Button
                      variant='ghost'
                      size='sm'
                      className='text-muted-foreground'
                      onClick={() => navigate({ to: '/workers' })}
                    >
                      {t('dashboard.viewAll')}
                      <ArrowRight className='ml-1 h-4 w-4' />
                    </Button>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        <NewSessionDialog
          open={newSessionDialogOpen}
          onOpenChange={setNewSessionDialogOpen}
          workers={workersQuery.data ?? []}
          isLoadingWorkers={workersQuery.isLoading}
          onCreateSession={handleCreateSession}
          isCreating={isCreatingSession}
        />
      </Main>
    </>
  )
}

function truncateId(id: string): string {
  if (id.length <= 12) return id
  return `${id.slice(0, 8)}...${id.slice(-4)}`
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}
