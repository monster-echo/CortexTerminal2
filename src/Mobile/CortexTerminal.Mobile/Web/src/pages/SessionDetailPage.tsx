import { useEffect, useState } from "react"
import { ArrowLeft } from "lucide-react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import type { TerminalGateway } from "../services/terminalGateway"
import { TerminalView } from "../terminal/TerminalView"
import type { ConsoleApi, SessionDetail } from "../services/consoleApi"

const statusColors: Record<string, string> = {
  live: "bg-emerald-500",
  detached: "bg-amber-500",
  exited: "bg-red-500",
  expired: "bg-zinc-500",
}

export function SessionDetailPage(props: {
  api: ConsoleApi
  sessionId: string
  navigate: (path: string) => void
  terminalGateway: TerminalGateway
}) {
  const { api, sessionId, navigate, terminalGateway } = props
  const [session, setSession] = useState<SessionDetail | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true
    setIsLoading(true)
    setSession(null)
    setErrorMessage(null)

    api
      .getSession(sessionId)
      .then((value) => {
        if (!isActive) return
        setSession(value)
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(error instanceof Error ? error.message : "Could not load session.")
      })
      .finally(() => {
        if (isActive) setIsLoading(false)
      })

    return () => {
      isActive = false
    }
  }, [api, sessionId])

  if (isLoading) {
    return (
      <div className="flex flex-col h-[calc(100vh-3.5rem)] space-y-3 p-1">
        <Skeleton className="h-10 w-48" />
        <Skeleton className="flex-1 rounded-xl" />
      </div>
    )
  }

  if (errorMessage) {
    return (
      <div className="p-4">
        <Alert variant="destructive">
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
        <Button onClick={() => navigate("/sessions")} variant="ghost" className="mt-3 w-full">
          <ArrowLeft className="mr-2 h-4 w-4" /> Back to sessions
        </Button>
      </div>
    )
  }

  if (!session) return null

  return (
    <div className="flex flex-col h-[calc(100vh-3.5rem)]">
      <div className="flex items-center gap-3 px-1 py-2 shrink-0">
        <Button onClick={() => navigate("/sessions")} variant="ghost" size="icon" className="h-8 w-8">
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <div className="min-w-0 flex-1">
          <p className="truncate font-mono text-sm font-semibold">{session.sessionId}</p>
          <p className="text-[11px] text-muted-foreground">on {session.workerId}</p>
        </div>
        <span
          className={`h-2.5 w-2.5 rounded-full shrink-0 ${statusColors[session.status] ?? "bg-zinc-400"}`}
        />
        <Badge variant="secondary" className="text-[10px] py-0 h-5">
          {session.status}
        </Badge>
      </div>

      <TerminalView gateway={terminalGateway} sessionId={session.sessionId} />
    </div>
  )
}
