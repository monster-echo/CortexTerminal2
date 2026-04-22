import { useEffect, useState } from "react"
import type { TerminalGateway } from "../services/terminalGateway"
import { TerminalView } from "../terminal/TerminalView"
import type { ConsoleApi, SessionDetail } from "../services/consoleApi"

export function SessionDetailPage(props: {
  api: ConsoleApi
  sessionId: string
  navigate: (path: string) => void
  terminalGateway: TerminalGateway
}) {
  const { api, sessionId, navigate, terminalGateway } = props
  const [session, setSession] = useState<SessionDetail | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    setIsLoading(true)
    setSession(null)
    setErrorMessage(null)

    api
      .getSession(sessionId)
      .then((value) => {
        if (!isActive) {
          return
        }

        setSession(value)
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return
        }

        setErrorMessage(error instanceof Error ? error.message : "Could not load session.")
      })
      .finally(() => {
        if (isActive) {
          setIsLoading(false)
        }
      })

    return () => {
      isActive = false
    }
  }, [api, sessionId])

  return (
    <section>
      <button onClick={() => navigate("/sessions")} type="button">
        Back to sessions
      </button>
      {isLoading ? <p>Loading session…</p> : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
      {session ? (
        <>
          <h2>Session {session.sessionId}</h2>
          <dl>
            <div>
              <dt>Worker</dt>
              <dd>{session.workerId}</dd>
            </div>
            <div>
              <dt>Status</dt>
              <dd>{session.status}</dd>
            </div>
          </dl>
          <TerminalView gateway={terminalGateway} sessionId={session.sessionId} />
        </>
      ) : null}
    </section>
  )
}
