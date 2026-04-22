import { useEffect, useState } from "react"
import { SessionList } from "../components/SessionList"
import type { ConsoleApi, SessionSummary } from "../services/consoleApi"

export function SessionListPage(props: {
  api: ConsoleApi
  navigate: (path: string) => void
}) {
  const { api, navigate } = props
  const [sessions, setSessions] = useState<SessionSummary[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [isCreatingSession, setIsCreatingSession] = useState(false)
  const [loadErrorMessage, setLoadErrorMessage] = useState<string | null>(null)
  const [createErrorMessage, setCreateErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    api
      .listSessions()
      .then((value) => {
        if (!isActive) {
          return
        }

        setSessions(value)
        setLoadErrorMessage(null)
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return
        }

        setLoadErrorMessage(error instanceof Error ? error.message : "Could not load sessions.")
      })
      .finally(() => {
        if (isActive) {
          setIsLoading(false)
        }
      })

    return () => {
      isActive = false
    }
  }, [api])

  const handleStartSession = async () => {
    setIsCreatingSession(true)
    setCreateErrorMessage(null)

    try {
      const created = await api.createSession()
      navigate(`/sessions/${created.sessionId}`)
    } catch (error) {
      setCreateErrorMessage(error instanceof Error ? error.message : "Could not start session.")
    } finally {
      setIsCreatingSession(false)
    }
  }

  return (
    <section>
      <h2>Sessions</h2>
      <p>Your sessions are the main entry point into the Gateway console.</p>
      <button disabled={isCreatingSession} onClick={() => void handleStartSession()} type="button">
        Start session
      </button>
      {isLoading ? <p>Loading sessions…</p> : null}
      {loadErrorMessage ? <p role="alert">{loadErrorMessage}</p> : null}
      {createErrorMessage ? <p role="status">{createErrorMessage}</p> : null}
      {!isLoading && !loadErrorMessage ? (
        <SessionList sessions={sessions} onOpen={(sessionId) => navigate(`/sessions/${sessionId}`)} />
      ) : null}
    </section>
  )
}
