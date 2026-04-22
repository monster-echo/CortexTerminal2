import { useEffect, useState } from "react"
import { SessionList } from "../components/SessionList"
import type { ConsoleApi, WorkerDetail } from "../services/consoleApi"

export function WorkerDetailPage(props: {
  api: ConsoleApi
  workerId: string
  navigate: (path: string) => void
}) {
  const { api, workerId, navigate } = props
  const [worker, setWorker] = useState<WorkerDetail | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    setIsLoading(true)
    setWorker(null)
    setErrorMessage(null)

    api
      .getWorker(workerId)
      .then((value) => {
        if (!isActive) {
          return
        }

        setWorker(value)
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return
        }

        setErrorMessage(error instanceof Error ? error.message : "Could not load worker.")
      })
      .finally(() => {
        if (isActive) {
          setIsLoading(false)
        }
      })

    return () => {
      isActive = false
    }
  }, [api, workerId])

  return (
    <section>
      <button onClick={() => navigate("/workers")} type="button">
        Back to workers
      </button>
      {isLoading ? <p>Loading worker…</p> : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
      {worker ? (
        <>
          <h2>Worker {worker.displayName}</h2>
          <dl>
            <div>
              <dt>Worker ID</dt>
              <dd>{worker.workerId}</dd>
            </div>
            <div>
              <dt>Status</dt>
              <dd>{worker.isOnline ? "Online" : "Offline"}</dd>
            </div>
          </dl>
          <h3>Hosted sessions</h3>
          <SessionList
            sessions={worker.sessions}
            onOpen={(sessionId) => navigate(`/sessions/${sessionId}`)}
          />
        </>
      ) : null}
    </section>
  )
}
