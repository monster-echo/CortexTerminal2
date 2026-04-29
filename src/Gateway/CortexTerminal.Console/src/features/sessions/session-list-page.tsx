import { useMemo, useState, useCallback } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { createConsoleApi, type SessionStatus } from '@/services/console-api'
import { Loader2, Plus, TerminalSquare, Trash2 } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
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

function createApi() {
  return createConsoleApi({
    getToken: () => useAuthStore.getState().auth.accessToken,
    onUnauthorized: () => useAuthStore.getState().auth.reset(),
    onTokenRefreshed: (newToken) =>
      useAuthStore.getState().auth.setAccessToken(newToken),
  })
}

type FilterTab = 'all' | 'live' | 'detached' | 'exited'

const DELETABLE_STATUSES: SessionStatus[] = ['detached', 'exited', 'expired']

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
  const api = useMemo(() => createApi(), [])

  const [filter, setFilter] = useState<FilterTab>('all')
  const [deleteTarget, setDeleteTarget] = useState<{
    sessionId: string
  } | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const [newSessionDialogOpen, setNewSessionDialogOpen] = useState(false)
  const [isCreatingSession, setIsCreatingSession] = useState(false)

  const workersQuery = useQuery({
    queryKey: ['workers', api],
    queryFn: () => api.listWorkers(),
  })

  const sessionsQuery = useQuery({
    queryKey: ['sessions', api],
    queryFn: () => api.listSessions(),
  })

  const allSessions = sessionsQuery.data ?? []
  const sessions = allSessions.filter((s) =>
    statusMatchesFilter(s.status, filter)
  )

  const handleDelete = useCallback(async () => {
    if (!deleteTarget) return
    setIsDeleting(true)
    try {
      await api.deleteSession(deleteTarget.sessionId)
      await queryClient.invalidateQueries({ queryKey: ['sessions'] })
      setDeleteTarget(null)
    } finally {
      setIsDeleting(false)
    }
  }, [api, deleteTarget, queryClient])

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
            Gateway Console
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
              Create a new terminal session or reconnect to an existing one.
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
            <CardTitle>Active and recent sessions</CardTitle>
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
                  : 'Could not load sessions.'}
              </p>
            ) : sessions.length === 0 ? (
              <div className='rounded-lg border border-dashed p-10 text-center'>
                <TerminalSquare className='mx-auto mb-3 size-8 text-muted-foreground' />
                <h3 className='text-lg font-semibold'>No sessions yet</h3>
                <p className='mt-1 text-sm text-muted-foreground'>
                  {filter === 'all'
                    ? 'Start a shell session and it will appear here.'
                    : 'No sessions match the selected filter.'}
                </p>
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Session</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Worker</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead>Last activity</TableHead>
                    <TableHead className='text-right'>Action</TableHead>
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
                            Open terminal
                          </Button>
                          <Button
                            variant='ghost'
                            size='icon'
                            className='size-8'
                            disabled={
                              !DELETABLE_STATUSES.includes(session.status)
                            }
                            onClick={() =>
                              setDeleteTarget({
                                sessionId: session.sessionId,
                              })
                            }
                          >
                            <Trash2 className='size-4' />
                          </Button>
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
          open={deleteTarget !== null}
          onOpenChange={(open) => {
            if (!open) setDeleteTarget(null)
          }}
          title={t('sessions.delete.confirm')}
          desc={t('sessions.delete.message')}
          confirmText={t('common.delete')}
          cancelBtnText={t('common.cancel')}
          destructive
          isLoading={isDeleting}
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
