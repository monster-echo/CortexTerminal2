import type { WorkerDetail, WorkerSummary } from "@/services/consoleApi"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

export function WorkerInfoCard(props: { worker: WorkerSummary | WorkerDetail }) {
  const { worker } = props

  return (
    <Card>
      <CardHeader>
        <CardTitle>{worker.displayName}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2 text-sm">
        <div className="flex items-center justify-between">
          <span className="text-muted-foreground">Worker ID</span>
          <code className="rounded bg-muted px-1 py-0.5 text-xs">{worker.workerId}</code>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-muted-foreground">Status</span>
          <Badge variant={worker.isOnline ? "default" : "secondary"}>
            {worker.isOnline ? "Online" : "Offline"}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-muted-foreground">Sessions</span>
          <span>{worker.sessionCount}</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-muted-foreground">Last seen</span>
          <span className="text-xs">{new Date(worker.lastSeenAt).toLocaleString()}</span>
        </div>
      </CardContent>
    </Card>
  )
}
