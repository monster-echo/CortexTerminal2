import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Link, useNavigate } from '@tanstack/react-router'
import { ConsoleApiError, type SessionDetail, type SessionSummary } from '@/services/console-api'
import {
  describeAgentKind,
  sessionDisplayTitle,
  type AgentTitleUpdatedFrame,
} from '@/services/agent-activity'
import { createTerminalGateway } from '@/services/terminal-gateway'
import { getSessionTerminalLogKey } from '@/terminal/terminal-event-log'
import { TerminalHeaderActions } from '@/terminal/terminal-header-actions'
import { TerminalView } from '@/terminal/terminal-view'
import { ArrowLeft, Loader2, Square, Trash2 } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth-store'
import {
  EMPTY_TERMINAL_EVENT_ENTRIES,
  useTerminalEventLogStore,
} from '@/stores/terminal-event-log-store'
import { getApi } from '@/lib/api'
import { useIsMobile } from '@/hooks/use-mobile'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/confirm-dialog'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { SessionDetailsSheet } from './session-details-sheet'
import { ArtifactFeedSheet } from './artifact-feed-sheet'
import { AgentActivitySheet } from './agent-activity-sheet'
import { useAgentActivity } from './use-agent-activity'

export function SessionDetailPage(props: { sessionId: string }) {
  const { sessionId } = props
  const { t } = useTranslation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const isMobile = useIsMobile()
  const [latencyMs, setLatencyMs] = useState<number | null>(null)
  const [latencyState, setLatencyState] = useState<
    'live' | 'measuring' | 'offline'
  >('measuring')
  const [terminateOpen, setTerminateOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [isTerminating, setIsTerminating] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const eventEntries = useTerminalEventLogStore(
    (state) =>
      state.logsByScope[getSessionTerminalLogKey(sessionId)] ??
      EMPTY_TERMINAL_EVENT_ENTRIES
  )

  const gateway = useMemo(
    () =>
      createTerminalGateway({
        accessTokenFactory: () => useAuthStore.getState().auth.accessToken,
      }),
    []
  )

  const agentActivity = useAgentActivity(sessionId)

  const sessionQuery = useQuery({
    queryKey: ['sessions', sessionId],
    queryFn: () => getApi().getSession(sessionId),
    retry: (failureCount, error) => {
      if (error instanceof ConsoleApiError && error.status === 404) {
        return false
      }
      return failureCount < 2
    },
  })

  const session = sessionQuery.data
  const canTerminate =
    session?.status === 'live' || session?.status === 'detached'
  const canDelete =
    session?.status === 'exited' || session?.status === 'expired'

  const refreshSessionState = async () => {
    await Promise.all([
      sessionQuery.refetch(),
      queryClient.invalidateQueries({ queryKey: ['sessions'] }),
    ])
  }

  const handleTerminate = async () => {
    setIsTerminating(true)
    try {
      await getApi().terminateSession(sessionId)
      setActionError(null)
      setTerminateOpen(false)
      await refreshSessionState()
    } catch (error) {
      setActionError(error instanceof Error ? error.message : t('common.error'))
    } finally {
      setIsTerminating(false)
    }
  }

  const handleDelete = async () => {
    setIsDeleting(true)
    try {
      await getApi().deleteSession(sessionId)
      setActionError(null)
      setDeleteOpen(false)
      await queryClient.invalidateQueries({ queryKey: ['sessions'] })
      navigate({ to: '/sessions' })
    } catch (error) {
      setActionError(error instanceof Error ? error.message : t('common.error'))
    } finally {
      setIsDeleting(false)
    }
  }

  if (sessionQuery.isLoading) {
    return (
      <>
        <Header>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/sessions'>
              <ArrowLeft /> {t('sessions.backToSessions')}
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

  const isNotFound =
    sessionQuery.error instanceof ConsoleApiError &&
    sessionQuery.error.status === 404

  if (isNotFound) {
    return (
      <>
        <Header>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/sessions'>
              <ArrowLeft /> {t('sessions.backToSessions')}
            </Link>
          </Button>
        </Header>
        <Main className='h-svh'>
          <div className='m-auto flex h-full w-full flex-col items-center justify-center gap-2'>
            <h1 className='text-[7rem] leading-tight font-bold'>404</h1>
            <span className='font-medium'>{t('sessions.notFoundTitle')}</span>
            <p className='text-center text-muted-foreground'>
              {t('sessions.notFoundDescription')}
            </p>
            <div className='mt-6 flex gap-4'>
              <Button onClick={() => navigate({ to: '/sessions' })}>
                {t('sessions.returnToSessions')}
              </Button>
            </div>
          </div>
        </Main>
      </>
    )
  }

  if (sessionQuery.isError || !session) {
    return (
      <>
        <Header>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/sessions'>
              <ArrowLeft /> {t('sessions.backToSessions')}
            </Link>
          </Button>
        </Header>
        <Main>
          <p className='text-sm text-destructive'>
            {sessionQuery.error instanceof Error
              ? sessionQuery.error.message
              : t('common.error')}
          </p>
        </Main>
      </>
    )
  }

  return (
    <>
      <Header>
        <div className='flex min-w-0 flex-1 items-center gap-3'>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/sessions'>
              <ArrowLeft /> {t('sessions.backToSessions')}
            </Link>
          </Button>
          <div className='min-w-0'>
            <h2 className='flex min-w-0 items-center gap-2 truncate text-sm font-semibold'>
              {session.agentKind && (
                <span className='shrink-0'>
                  {describeAgentKind(session.agentKind).icon}
                </span>
              )}
              <span className='truncate'>
                {sessionDisplayTitle(
                  session.inferredTitle,
                  session.sessionId
                )}
              </span>
            </h2>
            <p className='truncate font-mono text-xs text-muted-foreground'>
              {session.sessionId}
            </p>
          </div>
          <TerminalHeaderActions
            eventEntries={eventEntries}
            latencyMs={latencyMs}
            latencyState={latencyState}
          />
          {!isMobile && canTerminate && (
            <Button
              variant='destructive'
              size='sm'
              onClick={() => setTerminateOpen(true)}
            >
              <Square className='size-4' />
              {t('sessions.terminate.button')}
            </Button>
          )}
          {!isMobile && canDelete && (
            <Button
              variant='outline'
              size='sm'
              onClick={() => setDeleteOpen(true)}
            >
              <Trash2 className='size-4' />
              {t('sessions.delete.button')}
            </Button>
          )}

          {!isMobile && (
            <SessionDetailsSheet
              session={session}
              latencyMs={latencyMs}
              latencyState={latencyState}
            />
          )}

          {!isMobile && <ArtifactFeedSheet sessionId={sessionId} />}

          {!isMobile && (
            <AgentActivitySheet
              sessionId={sessionId}
              timeline={agentActivity.timeline}
              isLoading={agentActivity.isLoading}
              error={agentActivity.error}
            />
          )}
        </div>
      </Header>
      <Main fluid className='flex min-h-0 flex-1 flex-col overflow-hidden py-0'>
        <TerminalView
          gateway={gateway}
          sessionId={session.sessionId}
          workerId={session.workerId}
          sessionStatus={session.status}
          onLatencyChange={(nextLatencyMs, nextLatencyState) => {
            setLatencyMs(nextLatencyMs)
            setLatencyState(nextLatencyState)
          }}
          onSessionStatusChange={() => {
            void refreshSessionState()
          }}
          onAgentActivity={(envelope) => {
            agentActivity.pushLive(envelope)
            if (
              envelope.eventType === 'AgentTitleUpdated' &&
              envelope.frame.sessionId === sessionId
            ) {
              const newTitle = (envelope.frame as AgentTitleUpdatedFrame).title
              queryClient.setQueriesData<SessionSummary[]>(
                { queryKey: ['sessions'], exact: false },
                (old) =>
                  old
                    ? old.map((s) =>
                        s.sessionId === sessionId ? { ...s, inferredTitle: newTitle } : s,
                      )
                    : old,
              )
              queryClient.setQueryData<SessionDetail | undefined>(
                ['sessions', sessionId],
                (old) => (old ? { ...old, inferredTitle: newTitle } : old),
              )
            }
          }}
        />
      </Main>
      <ConfirmDialog
        open={terminateOpen}
        onOpenChange={(open) => {
          setTerminateOpen(open)
          if (!open) setActionError(null)
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
        open={deleteOpen}
        onOpenChange={(open) => {
          setDeleteOpen(open)
          if (!open) setActionError(null)
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
    </>
  )
}
