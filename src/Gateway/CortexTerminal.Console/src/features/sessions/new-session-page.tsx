import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate } from '@tanstack/react-router'
import { createConsoleApi } from '@/services/console-api'
import {
  getBootstrapTerminalLogKey,
  getSessionTerminalLogKey,
} from '@/terminal/terminal-event-log'
import { TerminalHeaderActions } from '@/terminal/terminal-header-actions'
import {
  TerminalViewport,
  type TerminalSize,
} from '@/terminal/terminal-viewport'
import { ArrowLeft } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { useTerminalEventLogStore } from '@/stores/terminal-event-log-store'
import { Button } from '@/components/ui/button'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { getOrStartSessionCreation } from './session-bootstrap'

function createApi() {
  return createConsoleApi({
    getToken: () => useAuthStore.getState().auth.accessToken,
    onUnauthorized: () => useAuthStore.getState().auth.reset(),
  })
}

export function NewSessionPage(props: { bootstrapId?: string }) {
  const { bootstrapId } = props
  const navigate = useNavigate()
  const api = useMemo(() => createApi(), [])
  const latestSizeRef = useRef<TerminalSize | null>(null)
  const creationStartedRef = useRef(false)
  const isActiveRef = useRef(true)
  const bootstrapLogKeyRef = useRef(
    bootstrapId
      ? getBootstrapTerminalLogKey(bootstrapId)
      : `bootstrap:missing:${crypto.randomUUID()}`
  )
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const eventEntries = useTerminalEventLogStore(
    (state) => state.logsByScope[bootstrapLogKeyRef.current] ?? []
  )
  const appendEvent = useTerminalEventLogStore((state) => state.appendEvent)
  const moveScope = useTerminalEventLogStore((state) => state.moveScope)
  const pruneLogs = useTerminalEventLogStore((state) => state.prune)

  const pushEvent = useCallback(
    (source: 'xterm' | 'session' | 'gateway', message: string) => {
      appendEvent(bootstrapLogKeyRef.current, source, message)
    },
    [appendEvent]
  )

  useEffect(() => {
    pruneLogs()
    pushEvent('session', 'New session screen mounted.')

    return () => {
      isActiveRef.current = false
    }
  }, [pruneLogs, pushEvent])

  const startCreation = useCallback(
    (size?: TerminalSize) => {
      const nextSize = size ?? latestSizeRef.current
      if (!bootstrapId || !nextSize || creationStartedRef.current) {
        return
      }

      creationStartedRef.current = true
      setErrorMessage(null)
      pushEvent(
        'gateway',
        `Creating session with measured size ${nextSize.columns}x${nextSize.rows}.`
      )

      void getOrStartSessionCreation(bootstrapId, () =>
        api.createSession(nextSize, bootstrapId)
      )
        .then((result) => {
          if (!isActiveRef.current) {
            return
          }

          pushEvent(
            'gateway',
            `Session ${result.sessionId} created successfully.`
          )
          moveScope(
            bootstrapLogKeyRef.current,
            getSessionTerminalLogKey(result.sessionId)
          )
          navigate({
            replace: true,
            to: '/sessions/$sessionId',
            params: { sessionId: result.sessionId },
          })
        })
        .catch((error: unknown) => {
          creationStartedRef.current = false
          if (!isActiveRef.current) {
            return
          }

          pushEvent(
            'gateway',
            error instanceof Error
              ? `Session creation failed: ${error.message}`
              : 'Session creation failed with an unknown error.'
          )
          setErrorMessage(
            error instanceof Error ? error.message : 'Could not create session.'
          )
        })
    },
    [api, bootstrapId, moveScope, navigate, pushEvent]
  )

  const handleResize = useCallback(
    (size: TerminalSize) => {
      latestSizeRef.current = size

      if (creationStartedRef.current) {
        return
      }

      pushEvent(
        'xterm',
        `Measured new session terminal at ${size.columns}x${size.rows}.`
      )
      if (!bootstrapId) {
        setErrorMessage(
          'Missing session bootstrap id. Please return and try again.'
        )
        pushEvent('gateway', 'Missing bootstrap id prevented session creation.')
        return
      }

      startCreation(size)
    },
    [bootstrapId, pushEvent, startCreation]
  )

  const handleViewportEvent = useCallback(
    (message: string) => {
      pushEvent('xterm', message)
    },
    [pushEvent]
  )

  const handleTerminalData = useCallback(() => undefined, [])

  return (
    <>
      <Header>
        <div className='flex min-w-0 flex-1 items-center gap-3'>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/sessions'>
              <ArrowLeft /> Back to sessions
            </Link>
          </Button>
          <TerminalHeaderActions
            eventEntries={eventEntries}
            latencyState='measuring'
          />
        </div>
      </Header>

      <Main fluid className='flex min-h-0 flex-1 flex-col overflow-hidden'>
        <TerminalViewport
          errorMessage={errorMessage}
          onData={handleTerminalData}
          onEvent={handleViewportEvent}
          onResize={handleResize}
        />
      </Main>
    </>
  )
}
