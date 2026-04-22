import { useEffect, useState } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
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
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold">Session {session?.sessionId ?? sessionId}</h1>
        <Button onClick={() => navigate("/sessions")} variant="ghost" size="sm">
          ← Back to sessions
        </Button>
      </div>
      {isLoading ? (
        <Card>
          <CardHeader>
            <Skeleton className="h-6 w-48" />
            <span className="sr-only">Loading session…</span>
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
      {session ? (
        <>
          <div className="grid gap-6 md:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>Session Info</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">Session ID</span>
                  <span className="font-mono text-sm">{session.sessionId}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">Worker</span>
                  <span className="font-mono text-sm">{session.workerId}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">Status</span>
                  <Badge variant="outline">{session.status}</Badge>
                </div>
              </CardContent>
            </Card>
            {worker ? (
              <Card>
                <CardHeader>
                  <CardTitle>Worker Info</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">Worker ID</span>
                    <span className="font-mono text-sm">{worker.workerId}</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">Name</span>
                    <span className="text-sm">{worker.displayName}</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">Status</span>
                    <Badge variant={worker.isOnline ? "default" : "secondary"}>
                      {worker.isOnline ? "Online" : "Offline"}
                    </Badge>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">Sessions</span>
                    <span className="text-sm">{worker.sessionCount}</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">Last seen</span>
                    <span className="text-sm">{new Date(worker.lastSeenAt).toLocaleString()}</span>
                  </div>
                </CardContent>
              </Card>
            ) : null}
          </div>
          <TerminalView gateway={terminalGateway} sessionId={session.sessionId} />
        </>
      ) : null}
    </div>
  )
}
