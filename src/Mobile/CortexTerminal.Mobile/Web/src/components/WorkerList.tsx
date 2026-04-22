import type { WorkerSummary } from "../services/consoleApi"

export function WorkerList(props: {
  workers: WorkerSummary[]
  onOpen: (workerId: string) => void
}) {
  const { workers, onOpen } = props

  if (workers.length === 0) {
    return <p>No workers found.</p>
  }

  return (
    <ul>
      {workers.map((worker) => (
        <li key={worker.workerId}>
          <strong>{worker.displayName}</strong>
          <div>{worker.sessionCount} sessions</div>
          <div>{worker.isOnline ? "Online" : "Offline"}</div>
          <button onClick={() => onOpen(worker.workerId)} type="button">
            Open worker
          </button>
        </li>
      ))}
    </ul>
  )
}
