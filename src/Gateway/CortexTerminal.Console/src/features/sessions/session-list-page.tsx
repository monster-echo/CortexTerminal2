import { useState, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useNavigate } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { type SessionStatus, type SessionSummary } from '@/services/console-api'
import { Loader2, Plus, Square, TerminalSquare, Trash2 } from 'lucide-react'
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
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { ConfirmDialog } from '@/components/confirm-dialog'
import { StatusDot } from '@/components/shared/status-dot'
import { StatusBadge } from '@/components/shared/status-badge'
import { NewSessionDialog } from '@/components/new-session-dialog'
import { useWorkers } from '@/hooks/use-workers'
import { useSessions } from '@/hooks/use-sessions'
import { useIsMobile } from '@/hooks/use-mobile'
import { getApi } from '@/lib/api'

type FilterTab = 'all' | 'live' | 'detached' | 'exited'

const TERMINABLE_STATUSES: SessionStatus[] = ['live', 'detached']
const DELETABLE_STATUSES: SessionStatus[] = ['exited', 'expired']

function statusMatchesFilter(status: SessionStatus, filter: FilterTab): boolean {
  if (filter === 'all') return true
  if (filter === 'live') return status === 'live'
  if (filter === 'detached') return status === 'detached'
  if (filter === 'exited') return status === 'exited' || status === 'expired'
  return true
}

export function SessionListPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const api = getApi()
  const isMobile = useIsMobile()

  const [filter, setFilter] = useState<FilterTab>('all')
  const [deleteTarget, setDeleteTarget] = useState<{
    sessionId: string
  } | null>(null)
  const [terminateTarget, setTerminateTarget] = useState<{
    sessionId: string
  } | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const [isTerminating, setIsTerminating] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const [newSessionDialogOpen, setNewSessionDialogOpen] = useState(false)
  const [isCreatingSession, setIsCreatingSession] = useState(false)

  const workersQuery = useWorkers()
  const sessionsQuery = useSessions()

  const allSessions = sessionsQuery.data ?? []
  const sessions = allSessions.filter((s) =>
    statusMatchesFilter(s.status, filter)
  )

  const handleDelete = useCallback(async () => {
    if (!deleteTarget) return
    setIsDeleting(true)
    try {
      await api.deleteSession(deleteTarget.sessionId)
      setActionError(null)
      await queryClient.invalidateQueries({ queryKey: ['sessions'] })
      setDeleteTarget(null)
    } catch (error) {
      setActionError(error instanceof Error ? error.message : t('common.error'))
    } finally {
      setIsDeleting(false)
    }
  }, [api, deleteTarget, queryClient, t])

  const handleTerminate = useCallback(async () => {
    if (!terminateTarget) return
    setIsTerminating(true)
    try {
      await api.terminateSession(terminateTarget.sessionId)
      setActionError(null)
      await queryClient.invalidateQueries({ queryKey: ['sessions'] })
      setTerminateTarget(null)
    } catch (error) {
      setActionError(error instanceof Error ? error.message : t('common.error'))
    } finally {
      setIsTerminating(false)
    }
  }, [api, queryClient, t, terminateTarget])

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
            {t('workers.gatewayConsole')}
          </p>
          <h1 className='text-lg font-semibold'>{t('sessions.title')}</h1>
        </div>
      </Header>

      <Main>
        <div className='mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between'>
          <div>
            <h2 className='text-2xl font-bold tracking-tight'>
              {t('sessions.title')}
            </h2>
            <p className='text-muted-foreground'>
              {t('sessions.description')}
            </p>
          </div>
          <Button
            onClick={() => setNewSessionDialogOpen(true)}
            disabled={isCreatingSession}
          >
            <Plus />
            {t('sessions.newSession')}
          </Button>
        </div>

        <Card>
          <CardHeader className='flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between'>
            <CardTitle>{t('sessions.activeAndRecent')}</CardTitle>
            <Tabs
              value={filter}
              onValueChange={(v) => setFilter(v as FilterTab)}
            >
              <TabsList>
                <TabsTrigger value='all'>
                  {t('sessions.filter.all')}
                </TabsTrigger>
                <TabsTrigger value='live'>
                  <StatusDot status='live' className='size-1.5' />
                  {t('sessions.filter.live')}
                </TabsTrigger>
                <TabsTrigger value='detached'>
                  <StatusDot status='detached' className='size-1.5' />
                  {t('sessions.filter.detached')}
                </TabsTrigger>
                <TabsTrigger value='exited'>
                  <StatusDot status='exited' className='size-1.5' />
                  {t('sessions.filter.exited')}
                </TabsTrigger>
              </TabsList>
            </Tabs>
          </CardHeader>
          <CardContent>
            {sessionsQuery.isLoading ? (
              <div className='flex items-center gap-2 text-sm text-muted-foreground'>
                <Loader2 className='size-4 animate-spin' /> {t('common.loading')}
              </div>
            ) : sessionsQuery.isError ? (
              <p className='text-sm text-destructive'>
                {sessionsQuery.error instanceof Error
                  ? sessionsQuery.error.message
                  : t('sessions.loadError')}
              </p>
            ) : sessions.length === 0 ? (
              <div className='rounded-lg border border-dashed p-10 text-center'>
                <TerminalSquare className='mx-auto mb-3 size-8 text-muted-foreground' />
                <h3 className='text-lg font-semibold'>{t('sessions.noSessions')}</h3>
                <p className='mt-1 text-sm text-muted-foreground'>
                  {filter === 'all'
                    ? t('sessions.noSessionsDescription')
                    : t('sessions.noMatchingSessions')}
                </p>
              </div>
            ) : isMobile ? (
              <MobileSessionList
                sessions={sessions}
                t={t}
                navigate={navigate}
              />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t('sessions.columns.session')}</TableHead>
                    <TableHead>{t('sessions.columns.status')}</TableHead>
                    <TableHead>{t('sessions.columns.worker')}</TableHead>
                    <TableHead>{t('sessions.columns.created')}</TableHead>
                    <TableHead>{t('sessions.columns.lastActivity')}</TableHead>
                    <TableHead className='text-right'>{t('sessions.columns.action')}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sessions.map((session) => (
                    <TableRow key={session.sessionId}>
                      <TableCell className='font-mono text-xs sm:text-sm'>
                        {session.sessionId}
                      </TableCell>
                      <TableCell>
                        <StatusBadge
                          status={session.status}
                          label={t(`sessions.status.${session.status}`)}
                        />
                      </TableCell>
                      <TableCell className='font-mono text-xs sm:text-sm'>
                        {session.workerId}
                      </TableCell>
                      <TableCell>{formatDateTime(session.createdAt)}</TableCell>
                      <TableCell>
                        {formatDateTime(session.lastActivityAt)}
                      </TableCell>
                      <TableCell className='text-right'>
                        <div className='flex items-center justify-end gap-1'>
                          <Button
                            variant='outline'
                            size='sm'
                            onClick={() =>
                              navigate({
                                to: '/sessions/$sessionId',
                                params: { sessionId: session.sessionId },
                              })
                            }
                          >
                            {t('sessions.openTerminal')}
                          </Button>
                          {TERMINABLE_STATUSES.includes(session.status) ? (
                            <Button
                              variant='destructive'
                              size='sm'
                              onClick={() =>
                                setTerminateTarget({
                                  sessionId: session.sessionId,
                                })
                              }
                            >
                              <Square className='size-4' />
                              {t('sessions.terminate.button')}
                            </Button>
                          ) : (
                            <Button
                              variant='ghost'
                              size='icon'
                              className='size-8'
                              disabled={!DELETABLE_STATUSES.includes(session.status)}
                              onClick={() =>
                                setDeleteTarget({
                                  sessionId: session.sessionId,
                                })
                              }
                            >
                              <Trash2 className='size-4' />
                            </Button>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <ConfirmDialog
          open={terminateTarget !== null}
          onOpenChange={(open) => {
            if (!open) {
              setTerminateTarget(null)
              setActionError(null)
            }
          }}
          title={t('sessions.terminate.confirm')}
          desc={t('sessions.terminate.message')}
          confirmText={t('sessions.terminate.button')}
          cancelBtnText={t('common.cancel')}
          destructive
          isLoading={isTerminating}
          error={actionError}
          handleConfirm={handleTerminate}
        />

        <ConfirmDialog
          open={deleteTarget !== null}
          onOpenChange={(open) => {
            if (!open) {
              setDeleteTarget(null)
              setActionError(null)
            }
          }}
          title={t('sessions.delete.confirm')}
          desc={t('sessions.delete.message')}
          confirmText={t('common.delete')}
          cancelBtnText={t('common.cancel')}
          destructive
          isLoading={isDeleting}
          error={actionError}
          handleConfirm={handleDelete}
        />

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

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function MobileSessionList({
  sessions,
  t,
  navigate,
}: {
  sessions: SessionSummary[]
  t: ReturnType<typeof useTranslation>['t']
  navigate: ReturnType<typeof useNavigate>
}) {
  return (
    <div className='flex flex-col divide-y'>
      {sessions.map((session) => (
        <div key={session.sessionId} className='flex items-center gap-3 py-3'>
          <div className='min-w-0 flex-1'>
            <div className='flex items-center gap-2'>
              <span className='truncate font-mono text-sm'>
                {session.sessionId}
              </span>
              <StatusBadge
                status={session.status}
                label={t(`sessions.status.${session.status}`)}
              />
            </div>
            <div className='mt-1 text-xs text-muted-foreground'>
              {formatDateTime(session.lastActivityAt)}
            </div>
          </div>
          <div className='flex shrink-0 items-center gap-1'>
            <Button
              variant='outline'
              size='sm'
              onClick={() =>
                navigate({
                  to: '/sessions/$sessionId',
                  params: { sessionId: session.sessionId },
                })
              }
            >
              {t('sessions.openTerminal')}
            </Button>
          </div>
        </div>
      ))}
    </div>
  )
}
