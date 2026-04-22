import { useEffect, useState } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"
import { Skeleton } from "@/components/ui/skeleton"
import { SessionList } from "@/components/SessionList"
import { WorkerInfoCard } from "@/components/WorkerInfoCard"
import type { ConsoleApi, WorkerDetail } from "@/services/consoleApi"

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
    <div className="space-y-6">
      <div>
        <Button onClick={() => navigate("/workers")} variant="ghost" size="sm">
          ← Back to workers
        </Button>
      </div>
      {isLoading ? (
        <Card>
          <CardHeader>
            <Skeleton className="h-6 w-48" />
          </CardHeader>
          <CardContent>
            <Skeleton className="h-20 w-full" />
          </CardContent>
        </Card>
      ) : null}
      {errorMessage ? (
        <Alert variant="destructive">
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
      ) : null}
      {worker ? (
        <>
          <WorkerInfoCard worker={worker} />
          <Card>
            <CardHeader>
              <CardTitle>Hosted sessions</CardTitle>
            </CardHeader>
            <CardContent>
              <SessionList
                sessions={worker.sessions}
                onOpen={(sessionId) => navigate(`/sessions/${sessionId}`)}
              />
            </CardContent>
          </Card>
        </>
      ) : null}
    </div>
  )
}
