import { useEffect, useState } from "react"
import type { TerminalGateway } from "../services/terminalGateway"
import { TerminalView } from "../terminal/TerminalView"
import type { ConsoleApi, SessionDetail, WorkerDetail } from "../services/consoleApi"

export function SessionDetailPage(props: {
  api: ConsoleApi
  sessionId: string
  navigate: (path: string) => void
  terminalGateway: TerminalGateway
}) {
  const { api, sessionId, navigate, terminalGateway } = props
  const [session, setSession] = useState<SessionDetail | null>(null)
  const [worker, setWorker] = useState<WorkerDetail | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    setIsLoading(true)
    setSession(null)
    setWorker(null)
    setErrorMessage(null)

    api
      .getSession(sessionId)
      .then((value) => {
        if (!isActive) {
          return
        }

        setSession(value)

        // Load worker info after session is loaded
        return api.getWorker(value.workerId)
      })
      .then((workerValue) => {
        if (!isActive || !workerValue) {
          return
        }

        setWorker(workerValue)
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
          <div style={{ display: "flex", gap: "1rem", marginBottom: "1rem" }}>
            <div style={{ flex: "1" }}>
              <h3>Session Info</h3>
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
            </div>
            {worker ? (
              <div style={{ flex: "1" }}>
                <h3>Worker Info</h3>
                <dl>
                  <div>
                    <dt>Worker ID</dt>
                    <dd>{worker.workerId}</dd>
                  </div>
                  <div>
                    <dt>Name</dt>
                    <dd>{worker.displayName}</dd>
                  </div>
                  <div>
                    <dt>Status</dt>
                    <dd>{worker.isOnline ? "Online" : "Offline"}</dd>
                  </div>
                  <div>
                    <dt>Sessions</dt>
                    <dd>{worker.sessionCount}</dd>
                  </div>
                  <div>
                    <dt>Last seen</dt>
                    <dd>{new Date(worker.lastSeenAt).toLocaleString()}</dd>
                  </div>
                </dl>
              </div>
            ) : null}
          </div>
          <TerminalView gateway={terminalGateway} sessionId={session.sessionId} />
        </>
      ) : null}
    </section>
  )
}
