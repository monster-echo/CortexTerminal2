import { useEffect, useState } from "react"
import { ChevronRight } from "lucide-react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Skeleton } from "@/components/ui/skeleton"
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
        if (!isActive) return
        setWorkers(value)
        setErrorMessage(null)
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(error instanceof Error ? error.message : "Could not load workers.")
      })
      .finally(() => {
        if (isActive) setIsLoading(false)
      })

    return () => {
      isActive = false
    }
  }, [api])

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-bold">Workers</h1>

      {errorMessage ? (
        <Alert variant="destructive">
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
      ) : null}

      {isLoading ? (
        <div className="space-y-2">
          <Skeleton className="h-[72px] rounded-xl" />
          <Skeleton className="h-[72px] rounded-xl" />
          <Skeleton className="h-[72px] rounded-xl" />
        </div>
      ) : workers.length === 0 ? (
        <div className="flex flex-col items-center gap-3 py-12 text-muted-foreground">
          <p className="text-sm">No workers connected</p>
        </div>
      ) : (
        <div className="space-y-2">
          {workers.map((worker) => (
            <div
              key={worker.workerId}
              className="flex items-center gap-3 rounded-xl border border-border bg-card p-3 cursor-pointer active:scale-[0.98] transition-transform"
              onClick={() => navigate(`/workers/${worker.workerId}`)}
            >
              <span
                className={`h-3 w-3 rounded-full shrink-0 ${worker.isOnline ? "bg-emerald-500" : "bg-zinc-400"}`}
              />
              <div className="min-w-0 flex-1">
                <p className="truncate font-semibold text-sm">{worker.displayName}</p>
                <p className="text-[11px] text-muted-foreground">
                  {worker.sessionCount} sessions &middot;{" "}
                  {new Date(worker.lastSeenAt).toLocaleTimeString([], {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </p>
              </div>
              <span className="text-xs font-medium shrink-0">
                {worker.isOnline ? (
                  <span className="text-emerald-500">Online</span>
                ) : (
                  <span className="text-muted-foreground">Offline</span>
                )}
              </span>
              <ChevronRight className="h-4 w-4 text-muted-foreground/50 shrink-0" />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
