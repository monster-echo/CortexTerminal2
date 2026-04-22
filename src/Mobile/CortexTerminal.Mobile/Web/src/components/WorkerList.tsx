import type { WorkerSummary } from "@/services/consoleApi"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"

export function WorkerList(props: {
  workers: WorkerSummary[]
  onOpen: (workerId: string) => void
}) {
  const { workers, onOpen } = props

  if (workers.length === 0) {
    return <p className="text-sm text-muted-foreground">No workers found.</p>
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Worker</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Sessions</TableHead>
          <TableHead className="text-right">Action</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {workers.map((worker) => (
          <TableRow key={worker.workerId}>
            <TableCell className="font-medium">{worker.displayName}</TableCell>
            <TableCell>
              <Badge variant={worker.isOnline ? "default" : "secondary"}>
                {worker.isOnline ? "Online" : "Offline"}
              </Badge>
            </TableCell>
            <TableCell>{worker.sessionCount} sessions</TableCell>
            <TableCell className="text-right">
              <Button onClick={() => onOpen(worker.workerId)} variant="ghost" size="sm">
                Open worker
              </Button>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}
