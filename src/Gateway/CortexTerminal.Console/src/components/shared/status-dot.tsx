import { cn } from '@/lib/utils'

type Status = 'live' | 'detached' | 'exited' | 'expired' | 'online' | 'offline'

const colorMap: Record<Status, string> = {
  live: 'bg-emerald-500',
  detached: 'bg-amber-500',
  exited: 'bg-red-500',
  expired: 'bg-zinc-400',
  online: 'bg-emerald-500',
  offline: 'bg-zinc-400',
}

interface StatusDotProps {
  status: Status
  className?: string
}

export function StatusDot({ status, className }: StatusDotProps) {
  return (
    <span
      className={cn('inline-block h-2 w-2 rounded-full shrink-0', colorMap[status], className)}
      aria-label={status}
    />
  )
}
