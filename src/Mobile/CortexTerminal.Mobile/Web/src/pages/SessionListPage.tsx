import { useEffect, useState } from "react"
import { Plus, ChevronRight } from "lucide-react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { Badge } from "@/components/ui/badge"
import type { ConsoleApi, SessionSummary } from "@/services/consoleApi"

const statusColors: Record<string, string> = {
  live: "bg-emerald-500",
  detached: "bg-amber-500",
  exited: "bg-red-500",
  expired: "bg-zinc-500",
}

export function SessionListPage(props: {
  api: ConsoleApi
  navigate: (path: string) => void
}) {
  const { api, navigate } = props
  const [sessions, setSessions] = useState<SessionSummary[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [isCreating, setIsCreating] = useState(false)
  const [filter, setFilter] = useState<"all" | "live" | "detached">("all")
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true

    api
      .listSessions()
      .then((value) => {
        if (!isActive) return
        setSessions(value)
        setErrorMessage(null)
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(error instanceof Error ? error.message : "Could not load sessions.")
      })
      .finally(() => {
        if (isActive) setIsLoading(false)
      })

    return () => {
      isActive = false
    }
  }, [api])

  const handleCreate = async () => {
    setIsCreating(true)
    setErrorMessage(null)
    try {
      const created = await api.createSession()
      navigate(`/sessions/${created.sessionId}`)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not start session.")
    } finally {
      setIsCreating(false)
    }
  }

  const filtered = sessions.filter((s) => {
    if (filter === "all") return true
    if (filter === "live") return s.status === "live"
    if (filter === "detached") return s.status === "detached"
    return true
  })

  const filters = [
    { key: "all", label: "All" },
    { key: "live", label: "Live" },
    { key: "detached", label: "Detached" },
  ] as const

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold">Sessions</h1>
        <Button onClick={() => void handleCreate()} disabled={isCreating} size="sm">
          <Plus className="mr-1 h-4 w-4" /> New
        </Button>
      </div>

      <div className="flex gap-1.5">
        {filters.map(({ key, label }) => (
          <button
            key={key}
            type="button"
            onClick={() => setFilter(key)}
            className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
              filter === key
                ? "bg-primary text-primary-foreground"
                : "bg-muted text-muted-foreground hover:bg-muted/80"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

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
      ) : filtered.length === 0 ? (
        <div className="flex flex-col items-center gap-3 py-12 text-muted-foreground">
          <p className="text-sm">No {filter === "all" ? "" : filter} sessions</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((session) => (
            <div
              key={session.sessionId}
              className="flex items-center gap-3 rounded-xl border border-border bg-card p-3 cursor-pointer active:scale-[0.98] transition-transform"
              onClick={() => navigate(`/sessions/${session.sessionId}`)}
            >
              <span
                className={`h-3 w-3 rounded-full shrink-0 ${statusColors[session.status] ?? "bg-zinc-400"}`}
              />
              <div className="min-w-0 flex-1">
                <p className="truncate font-mono text-xs font-semibold">{session.sessionId}</p>
                <p className="text-[11px] text-muted-foreground">
                  {session.workerId} &middot;{" "}
                  {new Date(session.lastActivityAt).toLocaleTimeString([], {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </p>
              </div>
              <div className="shrink-0">
                <Badge variant="secondary" className="text-[10px] py-0 h-5">
                  {session.status}
                </Badge>
              </div>
              <ChevronRight className="h-4 w-4 text-muted-foreground/50 shrink-0" />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
