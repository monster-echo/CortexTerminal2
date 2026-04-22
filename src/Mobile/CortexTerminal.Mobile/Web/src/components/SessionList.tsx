import type { SessionSummary } from "../services/consoleApi"

export function SessionList(props: {
  sessions: SessionSummary[]
  onOpen: (sessionId: string) => void
}) {
  const { sessions, onOpen } = props

  if (sessions.length === 0) {
    return <p>No sessions found.</p>
  }

  return (
    <ul>
      {sessions.map((session) => (
        <li key={session.sessionId}>
          <strong>{session.sessionId}</strong>
          <div>Worker {session.workerId}</div>
          <div>Status {session.status}</div>
          <button onClick={() => onOpen(session.sessionId)} type="button">
            Open session
          </button>
        </li>
      ))}
    </ul>
  )
}
