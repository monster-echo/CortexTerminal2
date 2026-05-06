import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useTranslation } from "react-i18next"
import { IonText } from "@ionic/react"
import type {
  TerminalGateway,
  TerminalGatewayConnection,
} from "../services/terminalGateway"
import {
  createTerminalSessionModel,
  type TerminalSessionState,
} from "./useTerminalSession"
import { createBrowserTerminal } from "./createBrowserTerminal"
import { StatusDot } from "../components/StatusDot"

export function TerminalView(props: {
  gateway: TerminalGateway
  sessionId: string
}) {
  const { t } = useTranslation()
  const { gateway, sessionId } = props
  const [status, setStatus] = useState<TerminalSessionState>("live")
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [cols, setCols] = useState<number | null>(null)
  const [rows, setRows] = useState<number | null>(null)
  const [latencyMs, setLatencyMs] = useState<number | null>(null)
  const [latencyState, setLatencyState] = useState<
    "measuring" | "live" | "offline"
  >("measuring")
  const connectionRef = useRef<TerminalGatewayConnection | null>(null)
  const terminalContainerRef = useRef<HTMLDivElement | null>(null)
  const browserTerminalRef = useRef<ReturnType<
    typeof createBrowserTerminal
  > | null>(null)
  const latencySeqRef = useRef(0)
  const pendingProbes = useRef(new Map<string, number>()).current

  const handleLatencyProbeAck = useCallback(
    (probeId: string) => {
      const startedAt = pendingProbes.get(probeId)
      if (startedAt === undefined) return
      pendingProbes.delete(probeId)
      setLatencyMs(performance.now() - startedAt)
      setLatencyState("live")
    },
    [pendingProbes],
  )

  const measureLatency = useCallback(() => {
    const conn = connectionRef.current
    if (!conn || status !== "live") return
    const probeId = `p-${++latencySeqRef.current}`
    pendingProbes.set(probeId, performance.now())
    setLatencyState("measuring")
    void conn.probeLatency(probeId)
    setTimeout(() => {
      if (pendingProbes.has(probeId)) {
        pendingProbes.delete(probeId)
        setLatencyState("offline")
      }
    }, 5000)
  }, [status])

  const session = useMemo(
    () =>
      createTerminalSessionModel({
        writeInput: (payload) => {
          void connectionRef.current?.writeInput(payload)
        },
        onStateChange: (nextStatus) => {
          setStatus(nextStatus)
          if (nextStatus !== "live") {
            pendingProbes.clear()
            setLatencyState("offline")
          }
        },
        onStream: ({ text }) => {
          browserTerminalRef.current?.write(text)
        },
      }),
    [sessionId, pendingProbes],
  )

  useEffect(() => {
    const element = terminalContainerRef.current
    if (!element) return

    const browserTerminal = createBrowserTerminal(element, (data) => {
      session.onTerminalData(data)
    })
    browserTerminalRef.current = browserTerminal
    browserTerminal.fit()

    const observer = new ResizeObserver(() => {
      const next = browserTerminal.fit()
      setCols(next.columns)
      setRows(next.rows)
      void connectionRef.current?.resize(next.columns, next.rows)
    })
    observer.observe(element)

    return () => {
      observer.disconnect()
      browserTerminal.dispose()
      browserTerminalRef.current = null
    }
  }, [session])

  useEffect(() => {
    let isActive = true
    setStatus("live")
    setErrorMessage(null)
    setLatencyMs(null)
    setLatencyState("measuring")

    void gateway
      .connect(sessionId, {
        onStdout: (payload) => session.onStdout(payload),
        onStderr: (payload) => session.onStderr(payload),
        onSessionReattached: (nextSessionId) =>
          session.onSessionReattached(nextSessionId),
        onReplayChunk: (payload, stream) =>
          session.onReplayChunk(payload, stream),
        onReplayCompleted: () => session.onReplayCompleted(),
        onSessionExpired: (reason) => {
          setErrorMessage(reason ?? t('terminal.expired'))
          session.onSessionExpired()
        },
        onLatencyProbeAck: handleLatencyProbeAck,
      })
      .then((connection) => {
        if (!isActive) {
          void connection.dispose()
          return
        }
        connectionRef.current = connection
        const browserTerminal = browserTerminalRef.current
        if (browserTerminal) {
          const size = browserTerminal.fit()
          setCols(size.columns)
          setRows(size.rows)
          void connection.resize(size.columns, size.rows)
        }
        measureLatency()
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(
          error instanceof Error
            ? error.message
            : t('terminal.connectError'),
        )
      })

    return () => {
      isActive = false
      const connection = connectionRef.current
      connectionRef.current = null
      if (connection) void connection.dispose()
    }
  }, [gateway, session, sessionId, measureLatency])

  useEffect(() => {
    const interval = setInterval(() => measureLatency(), 5000)
    return () => clearInterval(interval)
  }, [measureLatency])

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0 }}>
      {errorMessage && (
        <IonText color="danger">
          <p className="ion-padding-horizontal" style={{ fontSize: 13, margin: 0 }}>
            {errorMessage}
          </p>
        </IonText>
      )}
      <div ref={terminalContainerRef} className="terminal-bg" />
      <div className="terminal-status-bar">
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <StatusDot status={status === "live" ? "live" : "detached"} small />
          <span style={{ fontWeight: 500 }}>{status}</span>
        </div>
        <span>
          {latencyState === "measuring"
            ? t('terminal.e2eMeasuring')
            : latencyMs !== null
              ? t('terminal.e2eLive', { ms: Math.round(latencyMs) })
              : t('terminal.e2eMeasuring')}
        </span>
        <span>
          {cols !== null && rows !== null ? `${cols}\u00d7${rows}` : ""}
        </span>
      </div>
    </div>
  )
}
