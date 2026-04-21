import { useEffect, useMemo, useRef, useState } from "react"
import type { TerminalGateway, TerminalGatewayConnection } from "../services/terminalGateway"
import { createTerminalSessionModel, type TerminalSessionState } from "./useTerminalSession"

export function TerminalView(props: {
  gateway: TerminalGateway
  sessionId: string
}) {
  const { gateway, sessionId } = props
  const [status, setStatus] = useState<TerminalSessionState>("live")
  const [output, setOutput] = useState("")
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const connectionRef = useRef<TerminalGatewayConnection | null>(null)
  const session = useMemo(
    () =>
      createTerminalSessionModel({
        writeInput: (payload) => {
          void connectionRef.current?.writeInput(payload)
        },
        onStateChange: setStatus,
        onStream: ({ text }) => {
          setOutput((current) => current + text)
        },
      }),
    [sessionId]
  )

  useEffect(() => {
    let isActive = true
    setStatus("live")
    setOutput("")
    setErrorMessage(null)

    void gateway
      .connect(sessionId, {
        onStdout: (payload) => {
          session.onStdout(payload)
        },
        onStderr: (payload) => {
          session.onStderr(payload)
        },
        onSessionReattached: (nextSessionId) => {
          session.onSessionReattached(nextSessionId)
        },
        onReplayChunk: (payload, stream) => {
          session.onReplayChunk(payload, stream)
        },
        onReplayCompleted: () => {
          session.onReplayCompleted()
        },
        onSessionExpired: (reason) => {
          setErrorMessage(reason ?? "Session expired.")
          session.onSessionExpired()
        },
      })
      .then((connection) => {
        if (!isActive) {
          void connection.dispose()
          return
        }

        connectionRef.current = connection
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return
        }

        setErrorMessage(error instanceof Error ? error.message : "Could not connect terminal.")
      })

    return () => {
      isActive = false
      const connection = connectionRef.current
      connectionRef.current = null
      if (connection) {
        void connection.dispose()
      }
    }
  }, [gateway, session, sessionId])

  return (
    <div id="terminal-container">
      <div data-testid="terminal-status">{status}</div>
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
      <pre data-testid="terminal-output">{output}</pre>
      <button onClick={() => session.onTerminalData("\t")}>send-tab</button>
    </div>
  )
}
