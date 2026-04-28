import { useEffect, useState } from "react"
import { ArrowLeft, ChevronRight } from "lucide-react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { Badge } from "@/components/ui/badge"
import type { ConsoleApi, WorkerDetail } from "@/services/consoleApi"

const statusColors: Record<string, string> = {
  live: "bg-emerald-500",
  detached: "bg-amber-500",
  exited: "bg-red-500",
  expired: "bg-zinc-500",
}

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
        if (!isActive) return
        setWorker(value)
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(error instanceof Error ? error.message : "Could not load worker.")
      })
      .finally(() => {
        if (isActive) setIsLoading(false)
      })

    return () => {
      isActive = false
    }
  }, [api, workerId])

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-10 w-40" />
        <Skeleton className="h-32 rounded-xl" />
        <Skeleton className="h-48 rounded-xl" />
      </div>
    )
  }

  if (errorMessage) {
    return (
      <div className="space-y-4">
        <Button onClick={() => navigate("/workers")} variant="ghost" size="sm">
          <ArrowLeft className="mr-2 h-4 w-4" /> Back to workers
        </Button>
        <Alert variant="destructive">
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
      </div>
    )
  }

  if (!worker) return null

  return (
    <div className="space-y-4">
      <Button onClick={() => navigate("/workers")} variant="ghost" size="sm">
        <ArrowLeft className="mr-2 h-4 w-4" /> Back to workers
      </Button>

      <Card>
        <CardContent className="space-y-3 p-4">
          <div className="flex items-center gap-3">
            <span
              className={`h-3 w-3 rounded-full shrink-0 ${worker.isOnline ? "bg-emerald-500" : "bg-zinc-400"}`}
            />
            <div>
              <h2 className="text-lg font-bold">{worker.displayName}</h2>
              <p className="font-mono text-xs text-muted-foreground">{worker.workerId}</p>
            </div>
            <Badge variant={worker.isOnline ? "default" : "secondary"} className="ml-auto text-[10px]">
              {worker.isOnline ? "Online" : "Offline"}
            </Badge>
          </div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div>
              <span className="text-muted-foreground">Sessions</span>
              <p className="font-semibold">{worker.sessionCount}</p>
            </div>
            <div>
              <span className="text-muted-foreground">Last seen</span>
              <p className="font-semibold">
                {new Date(worker.lastSeenAt).toLocaleTimeString([], {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="space-y-1">
        <h3 className="text-sm font-semibold">Hosted Sessions</h3>
        {worker.sessions.length === 0 ? (
          <p className="text-xs text-muted-foreground py-4 text-center">No sessions on this worker</p>
        ) : (
          <div className="space-y-2">
            {worker.sessions.map((session) => (
              <div
                key={session.sessionId}
                className="flex items-center gap-3 rounded-xl border border-border bg-card p-3 cursor-pointer active:scale-[0.98] transition-transform"
                onClick={() => navigate(`/sessions/${session.sessionId}`)}
              >
                <span
                  className={`h-2.5 w-2.5 rounded-full shrink-0 ${statusColors[session.status] ?? "bg-zinc-400"}`}
                />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-mono text-xs font-medium">{session.sessionId}</p>
                  <p className="text-[11px] text-muted-foreground">
                    {new Date(session.lastActivityAt).toLocaleTimeString([], {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </p>
                </div>
                <Badge variant="secondary" className="text-[10px] py-0 h-5">
                  {session.status}
                </Badge>
                <ChevronRight className="h-4 w-4 text-muted-foreground/50 shrink-0" />
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
