import { useEffect, useState } from "react"
import {
  Activity,
  MonitorPlay,
  Server,
  Clock,
  ChevronRight,
} from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { Badge } from "@/components/ui/badge"
import type { ConsoleApi, SessionSummary } from "@/services/consoleApi"

const statusColors: Record<string, string> = {
  live: "bg-emerald-500",
  detached: "bg-amber-500",
  exited: "bg-red-500",
  expired: "bg-zinc-500",
}

export function DashboardPage(props: {
  api: ConsoleApi
  navigate: (path: string) => void
}) {
  const { api, navigate } = props
  const [sessions, setSessions] = useState<SessionSummary[]>([])
  const [workerCount, setWorkerCount] = useState(0)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    let isActive = true

    Promise.all([api.listSessions(), api.listWorkers()])
      .then(([sessionList, workerList]) => {
        if (!isActive) return
        setSessions(sessionList)
        setWorkerCount(workerList.length)
      })
      .catch(() => {})
      .finally(() => {
        if (isActive) setIsLoading(false)
      })

    return () => {
      isActive = false
    }
  }, [api])

  const liveSessions = sessions.filter((s) => s.status === "live").length
  const detachedSessions = sessions.filter((s) => s.status === "detached").length

  const stats = [
    {
      label: "Active",
      value: liveSessions,
      icon: Activity,
      color: "text-emerald-500",
      bg: "bg-emerald-500/10",
    },
    {
      label: "Detached",
      value: detachedSessions,
      icon: MonitorPlay,
      color: "text-amber-500",
      bg: "bg-amber-500/10",
    },
    {
      label: "Workers",
      value: workerCount,
      icon: Server,
      color: "text-blue-500",
      bg: "bg-blue-500/10",
    },
    {
      label: "Total",
      value: sessions.length,
      icon: Clock,
      color: "text-violet-500",
      bg: "bg-violet-500/10",
    },
  ]

  if (isLoading) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          {[1, 2, 3, 4].map((i) => (
            <Skeleton key={i} className="h-24 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-48 rounded-xl" />
      </div>
    )
  }

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3">
        {stats.map((stat) => {
          const Icon = stat.icon
          return (
            <Card key={stat.label} className="overflow-hidden">
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className={`rounded-lg ${stat.bg} p-2`}>
                    <Icon className={`h-4 w-4 ${stat.color}`} />
                  </div>
                </div>
                <p className="mt-3 text-2xl font-bold">{stat.value}</p>
                <p className="text-xs text-muted-foreground">{stat.label}</p>
              </CardContent>
            </Card>
          )
        })}
      </div>

      <div className="space-y-1">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-foreground">Recent Sessions</h2>
          <button
            type="button"
            onClick={() => navigate("/sessions")}
            className="flex items-center gap-1 text-xs text-primary hover:underline"
          >
            View all <ChevronRight className="h-3 w-3" />
          </button>
        </div>

        {sessions.length === 0 ? (
          <Card className="border-dashed">
            <CardContent className="flex flex-col items-center gap-2 py-8">
              <MonitorPlay className="h-8 w-8 text-muted-foreground/50" />
              <p className="text-sm text-muted-foreground">No sessions yet</p>
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-2">
            {sessions.slice(0, 5).map((session) => (
              <Card
                key={session.sessionId}
                className="cursor-pointer active:scale-[0.98] transition-transform"
                onClick={() => navigate(`/sessions/${session.sessionId}`)}
              >
                <CardContent className="flex items-center gap-3 p-3">
                  <span
                    className={`h-2.5 w-2.5 rounded-full shrink-0 ${statusColors[session.status] ?? "bg-zinc-400"}`}
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-mono text-xs font-medium">
                      {session.sessionId}
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      on {session.workerId}
                    </p>
                  </div>
                  <div className="text-right shrink-0">
                    <Badge variant="secondary" className="text-[10px] px-1.5 py-0 h-5">
                      {session.status}
                    </Badge>
                    <p className="mt-0.5 text-[10px] text-muted-foreground">
                      {new Date(session.lastActivityAt).toLocaleTimeString([], {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </p>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
