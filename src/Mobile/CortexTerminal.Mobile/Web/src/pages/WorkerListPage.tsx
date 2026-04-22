import { useEffect, useState } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { WorkerList } from "@/components/WorkerList"
import type { ConsoleApi, WorkerSummary } from "@/services/consoleApi"

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
    <Card>
      <CardHeader>
        <CardTitle>Workers</CardTitle>
        <CardDescription>
          Workers are a supporting operational view for your sessions.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
          </div>
        ) : null}
        {errorMessage ? (
          <Alert variant="destructive">
            <AlertDescription>{errorMessage}</AlertDescription>
          </Alert>
        ) : null}
        {!isLoading && !errorMessage ? (
          <WorkerList workers={workers} onOpen={(workerId) => navigate(`/workers/${workerId}`)} />
        ) : null}
      </CardContent>
    </Card>
  )
}
