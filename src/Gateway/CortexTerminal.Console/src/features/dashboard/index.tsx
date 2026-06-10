import { useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { useNavigate } from '@tanstack/react-router'
import { type SessionStatus } from '@/services/console-api'
import {
  Activity,
  Cpu,
  HardDrive,
  Loader2,
  MonitorSmartphone,
  Plus,
  Server,
  ShieldAlert,
  ArrowRight,
  Users,
  Wifi,
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
import { useAdminStats } from '@/hooks/use-admin-stats'
import { useAdminAuditStats } from '@/hooks/use-admin-audit-stats'
import { useAuthStore } from '@/stores/auth-store'
import { TrafficChart } from './components/traffic-chart'
import { ConnectionsChart } from './components/connections-chart'
import { SessionsActivityChart } from './components/sessions-activity-chart'
import { LoginTrendChart } from './components/login-trend-chart'
import { AuthProviderChart } from './components/auth-provider-chart'

const sessionStatusToBadge: Record<SessionStatus, SessionStatus | 'online' | 'offline'> = {
  live: 'live',
  detached: 'detached',
  expired: 'expired',
  exited: 'exited',
}

export function Dashboard() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const user = useAuthStore((state) => state.auth.user)
  const isAdmin = user?.role === 'admin'

  const statusBadgeLabel: Record<SessionStatus, string> = {
    live: t('sessions.status.live'),
    detached: t('sessions.status.detached'),
    expired: t('sessions.status.expired'),
    exited: t('sessions.status.exited'),
  }
  const [newSessionDialogOpen, setNewSessionDialogOpen] = useState(false)
  const [isCreatingSession, setIsCreatingSession] = useState(false)

  const workersQuery = useWorkers()
  const sessionsQuery = useSessions()
  const adminStatsQuery = useAdminStats()
  const auditStatsQuery = useAdminAuditStats()

  const workers = workersQuery.data ?? []
  const sessions = sessionsQuery.data ?? []
  const stats = adminStatsQuery.data

  const activeSessions = sessions.filter((s) => s.status === 'live').length
  const onlineWorkers = workers.filter((w) => w.isOnline).length
  const recentSessions = sessions.slice(0, 5)

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
        {/* Core Stat Cards */}
        <div className='grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6'>
          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>Connected Clients</CardTitle>
              <Wifi className='h-4 w-4 text-violet-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{stats?.connectedClients ?? '-'}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>{t('dashboard.onlineWorkers')}</CardTitle>
              <Server className='h-4 w-4 text-emerald-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{stats?.onlineWorkers ?? onlineWorkers}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>{t('dashboard.activeSessions')}</CardTitle>
              <MonitorSmartphone className='h-4 w-4 text-emerald-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{stats?.activeSessions ?? activeSessions}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>{t('dashboard.systemUptime')}</CardTitle>
              <Activity className='h-4 w-4 text-blue-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>
                {stats ? formatUptime(stats.uptimeSeconds) : t('dashboard.na')}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>Total Users</CardTitle>
              <Users className='h-4 w-4 text-sky-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>{stats?.totalUsers ?? '-'}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className='flex flex-row items-center justify-between pb-2'>
              <CardTitle className='text-sm font-medium'>Data Transferred</CardTitle>
              <Activity className='h-4 w-4 text-orange-500' />
            </CardHeader>
            <CardContent>
              <div className='text-2xl font-bold'>
                {stats ? formatBytes(stats.totalBytesTransferred) : '-'}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* System Health Cards */}
        {isAdmin && stats && (
          <div className='mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4'>
            <Card>
              <CardHeader className='flex flex-row items-center justify-between pb-2'>
                <CardTitle className='text-sm font-medium'>Memory</CardTitle>
                <HardDrive className='h-4 w-4 text-rose-500' />
              </CardHeader>
              <CardContent>
                <div className='text-2xl font-bold'>{formatBytes(stats.allocatedMemoryBytes)}</div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className='flex flex-row items-center justify-between pb-2'>
                <CardTitle className='text-sm font-medium'>Threads</CardTitle>
                <Cpu className='h-4 w-4 text-cyan-500' />
              </CardHeader>
              <CardContent>
                <div className='text-2xl font-bold'>{stats.threadCount}</div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className='flex flex-row items-center justify-between pb-2'>
                <CardTitle className='text-sm font-medium'>GC Collections</CardTitle>
                <Activity className='h-4 w-4 text-amber-500' />
              </CardHeader>
              <CardContent>
                <div className='text-2xl font-bold'>
                  {stats.gcGen0Collections}/{stats.gcGen1Collections}/{stats.gcGen2Collections}
                </div>
                <p className='text-xs text-muted-foreground'>Gen0 / Gen1 / Gen2</p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className='flex flex-row items-center justify-between pb-2'>
                <CardTitle className='text-sm font-medium'>Failed Login IPs</CardTitle>
                <ShieldAlert className='h-4 w-4 text-red-500' />
              </CardHeader>
              <CardContent>
                <div className='text-2xl font-bold'>{stats.failedLoginIpCount}</div>
              </CardContent>
            </Card>
          </div>
        )}

        {/* Charts */}
        {isAdmin && stats && stats.hourlyHistory.length > 0 && (
          <div className='mt-4 grid gap-4 md:grid-cols-2 lg:grid-cols-3'>
            <Card>
              <CardHeader>
                <CardTitle className='text-sm font-medium'>Connections (24h)</CardTitle>
              </CardHeader>
              <CardContent>
                <ConnectionsChart data={stats.hourlyHistory} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className='text-sm font-medium'>Traffic (24h)</CardTitle>
              </CardHeader>
              <CardContent>
                <TrafficChart data={stats.hourlyHistory} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className='text-sm font-medium'>Sessions (24h)</CardTitle>
              </CardHeader>
              <CardContent>
                <SessionsActivityChart data={stats.hourlyHistory} />
              </CardContent>
            </Card>
          </div>
        )}

        {/* Audit Analytics */}
        {isAdmin && auditStatsQuery.data && (
          <div className='mt-4 grid gap-4 md:grid-cols-2'>
            <Card>
              <CardHeader>
                <CardTitle className='text-sm font-medium'>Login Trend (7d)</CardTitle>
              </CardHeader>
              <CardContent>
                <LoginTrendChart data={auditStatsQuery.data.loginTrend} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className='text-sm font-medium'>Auth Provider Distribution</CardTitle>
              </CardHeader>
              <CardContent>
                <AuthProviderChart data={auditStatsQuery.data.authProviderDistribution} />
              </CardContent>
            </Card>
          </div>
        )}

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
              {workers.length === 0 ? (
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
                  {workers.map((worker) => {
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
                              {worker.name ?? worker.hostname ?? '-'}
                            </p>
                          </div>
                        </div>
                        <StatusBadge
                          status={status}
                          label={status === 'online' ? t('workers.status.online') : t('workers.status.offline')}
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

function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h ${minutes}m`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`
}
