import type { SessionSummary } from "@/services/consoleApi"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"

export function SessionList(props: {
  sessions: SessionSummary[]
  onOpen: (sessionId: string) => void
}) {
  const { sessions, onOpen } = props

  if (sessions.length === 0) {
    return <p className="text-sm text-muted-foreground">No sessions found.</p>
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Session ID</TableHead>
          <TableHead>Worker</TableHead>
          <TableHead>Status</TableHead>
          <TableHead className="text-right">Action</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {sessions.map((session) => (
          <TableRow key={session.sessionId}>
            <TableCell className="font-mono text-xs">{session.sessionId}</TableCell>
            <TableCell className="font-mono text-xs">{session.workerId}</TableCell>
            <TableCell>
              <Badge variant="secondary">{session.status}</Badge>
            </TableCell>
            <TableCell className="text-right">
              <Button onClick={() => onOpen(session.sessionId)} variant="ghost" size="sm">
                Open session
              </Button>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}
