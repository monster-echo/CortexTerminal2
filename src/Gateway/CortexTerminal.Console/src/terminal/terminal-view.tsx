import { useCallback, useEffect, useRef, useState } from 'react'
import type {
  TerminalGateway,
  TerminalGatewayConnection,
} from '@/services/terminal-gateway'
import { useTerminalEventLogStore } from '@/stores/terminal-event-log-store'
import { getSessionTerminalLogKey } from './terminal-event-log'
import {
  TerminalViewport,
  type BrowserTerminal,
  type TerminalSize,
} from './terminal-viewport'
import { TerminalStatusBar } from './terminal-status-bar'
import { TerminalVirtualKeys } from './terminal-virtual-keys'
import { createTerminalSessionModel } from './useTerminalSession'
import type { SessionStatus } from '@/services/console-api'

export function TerminalView(props: {
  gateway: TerminalGateway
  sessionId: string
  workerId?: string
  sessionStatus?: SessionStatus
  onLatencyChange?: (
    latencyMs: number | null,
    state: 'live' | 'measuring' | 'offline'
  ) => void
}) {
  const { gateway, onLatencyChange, sessionId, workerId, sessionStatus } =
    props
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [statusMessage, setStatusMessage] = useState('Connecting to terminal…')
  const [latencyProbeGeneration, setLatencyProbeGeneration] = useState(0)
  const [terminalSize, setTerminalSize] = useState<TerminalSize>({
    columns: 80,
    rows: 24,
  })
  const [latencyMs, setLatencyMs] = useState<number | null>(null)
  const [latencyState, setLatencyState] = useState<
    'live' | 'measuring' | 'offline'
  >('measuring')
  const connectionRef = useRef<TerminalGatewayConnection | null>(null)
  const browserTerminalRef = useRef<BrowserTerminal | null>(null)
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

  useEffect(() => {
    pruneLogs()
    pushEvent('gateway', `Connecting to session ${sessionId}.`)
  }, [pruneLogs, pushEvent, sessionId])

  useEffect(() => {
    onLatencyChange?.(null, 'measuring')
  }, [onLatencyChange, sessionId])

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
        setStatusMessage('Terminal ready. Waiting for session connection…')
        return
      }

      const size = browserTerminal.fit()
      setTerminalSize({ columns: size.columns, rows: size.rows })
      setStatusMessage(
        `Live terminal attached at ${size.columns}x${size.rows}.`
      )
      pushEvent(
        'gateway',
        `Syncing server PTY size to ${size.columns}x${size.rows}.`
      )
      void connection.resize(size.columns, size.rows)
    },
    [pushEvent]
  )

  const handleTerminalResize = useCallback(
    (size: TerminalSize) => {
      setTerminalSize({ columns: size.columns, rows: size.rows })
      setStatusMessage(`Terminal resized to ${size.columns}x${size.rows}.`)
      pushEvent(
        'xterm',
        `Viewport resize observed at ${size.columns}x${size.rows}.`
      )
      void connectionRef.current?.resize(size.columns, size.rows)
    },
    [pushEvent]
  )

  const handleTerminalData = useCallback((data: string) => {
    sessionRef.current?.onTerminalData(data)
  }, [])

  const handleViewportEvent = useCallback(
    (message: string) => {
      pushEvent('xterm', message)
    },
    [pushEvent]
  )

  const handleLatencyChange = useCallback(
    (nextLatencyMs: number | null, nextState: 'live' | 'measuring' | 'offline') => {
      setLatencyMs(nextLatencyMs)
      setLatencyState(nextState)
      onLatencyChange?.(nextLatencyMs, nextState)
    },
    [onLatencyChange]
  )

  useEffect(() => {
    let isActive = true

    void gateway
      .connect(sessionId, {
        onStdout: (payload) => {
          setStatusMessage('Terminal stream connected.')
          sessionRef.current?.onStdout(payload)
        },
        onStderr: (payload) => {
          pushEvent(
            'session',
            `Received stderr chunk (${payload.length} bytes).`
          )
          sessionRef.current?.onStderr(payload)
        },
        onSessionReattached: (nextSessionId) => {
          setStatusMessage('Session reattached. Replaying terminal output…')
          pushEvent('gateway', `Session reattached as ${nextSessionId}.`)
          sessionRef.current?.onSessionReattached(nextSessionId)
        },
        onReplayChunk: (payload, stream) => {
          setStatusMessage('Replaying buffered terminal output…')
          pushEvent(
            'session',
            `Replay ${stream} chunk received (${payload.length} bytes).`
          )
          sessionRef.current?.onReplayChunk(payload, stream)
        },
        onReplayCompleted: () => {
          setStatusMessage('Terminal live.')
          pushEvent('gateway', 'Replay completed; terminal is live.')
          sessionRef.current?.onReplayCompleted()
        },
        onSessionExpired: (reason) => {
          setErrorMessage(reason ?? 'Session expired.')
          setStatusMessage('Session is no longer available.')
          handleLatencyChange(null, 'offline')
          pushEvent(
            'gateway',
            `Session expired: ${reason ?? 'unknown reason'}.`
          )
          sessionRef.current?.onSessionExpired()
        },
      })
      .then((connection) => {
        if (!isActive) {
          void connection.dispose()
          return
        }

        connectionRef.current = connection
        setErrorMessage(null)
        setStatusMessage('Transport connected. Waiting for terminal sizing…')
        handleLatencyChange(null, 'measuring')
        setLatencyProbeGeneration((current) => current + 1)
        pushEvent('gateway', 'Transport connected to terminal hub.')
        const browserTerminal = browserTerminalRef.current
        if (browserTerminal) {
          const size = browserTerminal.fit()
          setTerminalSize({ columns: size.columns, rows: size.rows })
          setStatusMessage(`Terminal ready at ${size.columns}x${size.rows}.`)
          pushEvent(
            'gateway',
            `Sending initial size ${size.columns}x${size.rows} to server.`
          )
          void connection.resize(size.columns, size.rows)
        }
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return
        }

        setStatusMessage('Terminal connection failed.')
        handleLatencyChange(null, 'offline')
        pushEvent(
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
        pushEvent('gateway', 'Disconnecting terminal transport.')
        void connection.dispose()
      }
    }
  }, [gateway, handleLatencyChange, pushEvent, sessionId])

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

  const effectiveStatus: SessionStatus | 'offline' =
    sessionStatus ?? (latencyState === 'offline' ? 'offline' : 'live')

  return (
    <div className='flex h-full min-h-0 flex-col'>
      <TerminalViewport
        errorMessage={errorMessage}
        onData={handleTerminalData}
        onEvent={handleViewportEvent}
        onReady={handleTerminalReady}
        onResize={handleTerminalResize}
      />
      <TerminalVirtualKeys onSendData={handleTerminalData} />
      <TerminalStatusBar
        status={effectiveStatus}
        sessionId={sessionId}
        workerId={workerId}
        latencyMs={latencyMs}
        cols={terminalSize.columns}
        rows={terminalSize.rows}
        statusMessage={statusMessage}
      />
    </div>
  )
}
