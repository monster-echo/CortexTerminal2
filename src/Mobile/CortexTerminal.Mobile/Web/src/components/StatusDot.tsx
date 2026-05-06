const statusColorClass: Record<string, string> = {
  live: "success",
  online: "success",
  detached: "warning",
  exited: "danger",
  expired: "medium",
  offline: "medium",
}

export function StatusDot({
  status,
  small,
}: {
  status: string
  small?: boolean
}) {
  const size = small ? "status-dot-sm" : "status-dot"
  const color = statusColorClass[status] ?? "medium"
  return <span className={`${size} ${size}-${color}`} />
}
