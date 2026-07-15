import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from '@tanstack/react-router'
import type { SessionStatus } from '@/services/console-api'
import type {
  AgentActivityEnvelope,
  TerminalGateway,
  TerminalGatewayConnection,
} from '@/services/terminal-gateway'
import { useTranslation } from 'react-i18next'
import { useIsMobile } from '@/hooks/use-mobile'
import { useTerminalEventLogStore } from '@/stores/terminal-event-log-store'
import { getSessionTerminalLogKey } from './terminal-event-log'
import {
  TerminalViewport,
  type BrowserTerminal,
  type TerminalSize,
} from './terminal-viewport'
import {
  TerminalVirtualKeys,
  applyCtrlModifier,
  applyAltModifier,
} from './terminal-virtual-keys'
import { createTerminalSessionModel } from './useTerminalSession'

export function TerminalView(props: {
  gateway: TerminalGateway
  sessionId: string
  onLatencyChange?: (
    latencyMs: number | null,
    state: 'live' | 'measuring' | 'offline'
  ) => void
  onSessionStatusChange?: (
    status: Extract<SessionStatus, 'expired' | 'exited'>,
    reason?: string | null
  ) => void
  onAgentActivity?: (envelope: AgentActivityEnvelope) => void
}) {
  const {
    gateway,
    onLatencyChange,
    onSessionStatusChange,
    onAgentActivity,
    sessionId,
  } = props
  const navigate = useNavigate()
  const { t } = useTranslation()
  const isMobile = useIsMobile()
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [latencyProbeGeneration, setLatencyProbeGeneration] = useState(0)
  const [ctrlActive, setCtrlActive] = useState(false)
  const [altActive, setAltActive] = useState(false)
  const [sessionEnd, setSessionEnd] = useState<{
    sessionId: string
    status: 'expired' | 'exited'
    reason: string | null
  } | null>(null)
  const connectionRef = useRef<TerminalGatewayConnection | null>(null)
  const browserTerminalRef = useRef<BrowserTerminal | null>(null)
  const lastSyncedSizeRef = useRef<TerminalSize | null>(null)
  const sessionRef = useRef<ReturnType<
    typeof createTerminalSessionModel
  > | null>(null)
  const scopeKey = getSessionTerminalLogKey(sessionId)
  const appendEvent = useTerminalEventLogStore((state) => state.appendEvent)
  const pruneLogs = useTerminalEventLogStore((state) => state.prune)

  const pushEvent = useCallback(
    (source: 'xterm' | 'session' | 'gateway', message: string) => {
      appendEvent(scopeKey, source, message)
    },
    [appendEvent, scopeKey]
  )
  const pushEventRef = useRef(pushEvent)
  const onLatencyChangeRef = useRef(onLatencyChange)
  const onSessionStatusChangeRef = useRef(onSessionStatusChange)
  const onAgentActivityRef = useRef(onAgentActivity)

  useEffect(() => {
    pushEventRef.current = pushEvent
    onLatencyChangeRef.current = onLatencyChange
    onSessionStatusChangeRef.current = onSessionStatusChange
    onAgentActivityRef.current = onAgentActivity
  }, [onLatencyChange, onSessionStatusChange, onAgentActivity, pushEvent])

  useEffect(() => {
    pruneLogs()
    pushEvent('gateway', `Connecting to session ${sessionId}.`)
  }, [pruneLogs, pushEvent, sessionId])

  useEffect(() => {
    onLatencyChangeRef.current?.(null, 'measuring')
  }, [sessionId])

  useEffect(() => {
    sessionRef.current = createTerminalSessionModel({
      writeInput: (payload) => {
        void connectionRef.current?.writeInput(payload)
      },
      onStream: ({ text }) => {
        browserTerminalRef.current?.write(text)
      },
    })

    return () => {
      sessionRef.current = null
    }
  }, [])

  const handleTerminalReady = useCallback(
    (browserTerminal: BrowserTerminal | null) => {
      browserTerminalRef.current = browserTerminal
      if (!browserTerminal) {
        pushEvent('xterm', 'Browser terminal detached from the page.')
        return
      }

      pushEvent('xterm', 'Browser terminal attached and ready for resize.')

      const connection = connectionRef.current
      if (!connection) {
        return
      }

      browserTerminal.fit()
    },
    [pushEvent]
  )

  const handleTerminalResize = useCallback(
    (size: TerminalSize) => {
      const lastSyncedSize = lastSyncedSizeRef.current
      if (
        lastSyncedSize?.columns === size.columns &&
        lastSyncedSize.rows === size.rows
      ) {
        return
      }

      lastSyncedSizeRef.current = size
      pushEvent(
        'xterm',
        `Viewport resize observed at ${size.columns}x${size.rows}.`
      )
      void connectionRef.current?.resize(size.columns, size.rows)
    },
    [pushEvent]
  )

  const handleTerminalData = useCallback(
    (data: string) => {
      let processed = data
      if (ctrlActive) {
        processed = applyCtrlModifier(processed)
      }
      if (altActive) {
        processed = applyAltModifier(processed)
      }
      sessionRef.current?.onTerminalData(processed)
    },
    [ctrlActive, altActive]
  )

  const handleCtrlToggle = useCallback(() => {
    setCtrlActive((v) => !v)
  }, [])

  const handleAltToggle = useCallback(() => {
    setAltActive((v) => !v)
  }, [])

  const handleModifiersClear = useCallback(() => {
    setCtrlActive(false)
    setAltActive(false)
  }, [])

  const handleViewportEvent = useCallback(
    (message: string) => {
      pushEvent('xterm', message)
    },
    [pushEvent]
  )

  const handleLatencyChange = useCallback(
    (
      nextLatencyMs: number | null,
      nextState: 'live' | 'measuring' | 'offline'
    ) => {
      onLatencyChangeRef.current?.(nextLatencyMs, nextState)
    },
    []
  )

  useEffect(() => {
    let isActive = true
    const pe = pushEventRef.current

    void gateway
      .connect(sessionId, {
        onStdout: (payload) => {
          sessionRef.current?.onStdout(payload)
        },
        onStderr: (payload) => {
          pe('session', `Received stderr chunk (${payload.length} bytes).`)
          sessionRef.current?.onStderr(payload)
        },
        onSessionReattached: (nextSessionId) => {
          browserTerminalRef.current?.clear()
          pe('gateway', `Session reattached as ${nextSessionId}.`)
          sessionRef.current?.onSessionReattached(nextSessionId)
        },
        onReplayChunk: (payload, stream) => {
          pe(
            'session',
            `Replay ${stream} chunk received (${payload.length} bytes).`
          )
          sessionRef.current?.onReplayChunk(payload, stream)
        },
        onReplayCompleted: () => {
          pe('gateway', 'Replay completed; terminal is live.')
          sessionRef.current?.onReplayCompleted()
        },
        onSessionExpired: (reason) => {
          setSessionEnd({
            sessionId,
            status: 'expired',
            reason: reason ?? null,
          })
          setErrorMessage(reason ?? 'Session expired.')
          handleLatencyChange(null, 'offline')
          pe('gateway', `Session expired: ${reason ?? 'unknown reason'}.`)
          sessionRef.current?.onSessionExpired()
          onSessionStatusChangeRef.current?.('expired', reason ?? null)
          const connection = connectionRef.current
          connectionRef.current = null
          if (connection) {
            void connection.dispose()
          }
        },
        onSessionExited: (reason) => {
          setSessionEnd({
            sessionId,
            status: 'exited',
            reason: reason ?? null,
          })
          setErrorMessage(null)
          handleLatencyChange(null, 'offline')
          pe('gateway', `Session exited: ${reason ?? 'unknown reason'}.`)
          onSessionStatusChangeRef.current?.('exited', reason ?? null)
          const connection = connectionRef.current
          connectionRef.current = null
          if (connection) {
            void connection.dispose()
          }
        },
        onAgentActivity: (envelope) => {
          onAgentActivityRef.current?.(envelope)
        },
      })
      .then((connection) => {
        if (!isActive) {
          void connection.dispose()
          return
        }

        connectionRef.current = connection
        setErrorMessage(null)
        handleLatencyChange(null, 'measuring')
        setLatencyProbeGeneration((current) => current + 1)
        pe('gateway', 'Transport connected to terminal hub.')
        const browserTerminal = browserTerminalRef.current
        if (browserTerminal) {
          browserTerminal.fit()
        }
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return
        }

        handleLatencyChange(null, 'offline')
        pe(
          'gateway',
          error instanceof Error
            ? `Connection failed: ${error.message}`
            : 'Connection failed with an unknown error.'
        )
        setErrorMessage(
          error instanceof Error ? error.message : 'Could not connect terminal.'
        )
      })

    return () => {
      isActive = false
      const connection = connectionRef.current
      connectionRef.current = null
      handleLatencyChange(null, 'offline')
      if (connection) {
        pe('gateway', 'Disconnecting terminal transport.')
        void connection.dispose()
      }
    }
  }, [gateway, handleLatencyChange, sessionId])

  useEffect(() => {
    if (latencyProbeGeneration === 0) {
      return
    }

    let isActive = true
    let probeTimer: number | undefined

    const measureLatency = async () => {
      const connection = connectionRef.current
      if (!connection) {
        return
      }

      const startedAt = performance.now()
      const probeId = crypto.randomUUID()

      try {
        await connection.probeLatency(probeId)
      } catch {
        if (isActive) {
          handleLatencyChange(null, 'offline')
        }
        return
      }

      if (!isActive) {
        return
      }

      handleLatencyChange(performance.now() - startedAt, 'live')
    }

    const scheduleLatencyProbe = () => {
      void measureLatency()
      probeTimer = window.setInterval(() => {
        void measureLatency()
      }, 15000)
    }

    scheduleLatencyProbe()

    return () => {
      isActive = false
      if (probeTimer !== undefined) {
        window.clearInterval(probeTimer)
      }
    }
  }, [latencyProbeGeneration, handleLatencyChange, sessionId])

  const currentSessionEnd =
    sessionEnd?.sessionId === sessionId ? sessionEnd : null

  const isSessionGone =
    currentSessionEnd?.status === 'expired' &&
    (currentSessionEnd.reason === 'session-not-found' ||
      currentSessionEnd.reason === 'session-expired')

  // Auto-redirect to sessions list when the session no longer exists on the server
  useEffect(() => {
    if (!isSessionGone) {
      return
    }

    const timer = setTimeout(() => {
      navigate({ to: '/sessions' })
    }, 5000)

    return () => clearTimeout(timer)
  }, [isSessionGone, navigate])

  return (
    <div className='flex h-full min-h-0 flex-col'>
      {isSessionGone && (
        <div className='flex items-center gap-2 rounded-lg bg-destructive/90 px-0 py-2 text-sm text-white md:px-4'>
          <span>{t('terminal.sessionGoneNotice')}</span>
          <button
            type='button'
            className='ml-auto shrink-0 rounded bg-white/20 px-3 py-1 text-xs font-medium text-white hover:bg-white/30'
            onClick={() => navigate({ to: '/sessions' })}
          >
            {t('sessions.returnToSessions')}
          </button>
        </div>
      )}
      <TerminalViewport
        errorMessage={isSessionGone ? null : errorMessage}
        onData={handleTerminalData}
        onEvent={handleViewportEvent}
        onReady={handleTerminalReady}
        onResize={handleTerminalResize}
      />
      {isMobile && (
        <TerminalVirtualKeys
          onSendData={handleTerminalData}
          ctrlActive={ctrlActive}
          altActive={altActive}
          onCtrlToggle={handleCtrlToggle}
          onAltToggle={handleAltToggle}
          onModifiersClear={handleModifiersClear}
        />
      )}
    </div>
  )
}
