import { useEffect, useState } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { SessionList } from "@/components/SessionList"
import type { ConsoleApi, SessionSummary } from "@/services/consoleApi"

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
    <Card>
      <CardHeader>
        <div className="flex items-start justify-between">
          <div>
            <CardTitle>Sessions</CardTitle>
            <CardDescription>
              Your sessions are the main entry point into the Gateway console.
            </CardDescription>
          </div>
          <Button disabled={isCreatingSession} onClick={() => void handleStartSession()}>
            Start session
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
          </div>
        ) : null}
        {loadErrorMessage ? (
          <Alert variant="destructive">
            <AlertDescription>{loadErrorMessage}</AlertDescription>
          </Alert>
        ) : null}
        {createErrorMessage ? (
          <Alert variant="destructive">
            <AlertDescription role="status">{createErrorMessage}</AlertDescription>
          </Alert>
        ) : null}
        {!isLoading && !loadErrorMessage ? (
          <SessionList sessions={sessions} onOpen={(sessionId) => navigate(`/sessions/${sessionId}`)} />
        ) : null}
      </CardContent>
    </Card>
  )
}
