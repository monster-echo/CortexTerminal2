import { useEffect, useState } from "react"
import { WorkerList } from "../components/WorkerList"
import type { ConsoleApi, WorkerSummary } from "../services/consoleApi"

export function WorkerListPage(props: {
  api: ConsoleApi
  navigate: (path: string) => void
}) {
  const { api, navigate } = props
  const [workers, setWorkers] = useState<WorkerSummary[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    api
      .listWorkers()
      .then((value) => {
        if (!isActive) {
          return
        }

        setWorkers(value)
        setErrorMessage(null)
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return
        }

        setErrorMessage(error instanceof Error ? error.message : "Could not load workers.")
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

  return (
    <section>
      <h2>Workers</h2>
      <p>Workers are a supporting operational view for your sessions.</p>
      {isLoading ? <p>Loading workers…</p> : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
      {!isLoading && !errorMessage ? (
        <WorkerList workers={workers} onOpen={(workerId) => navigate(`/workers/${workerId}`)} />
      ) : null}
    </section>
  )
}
