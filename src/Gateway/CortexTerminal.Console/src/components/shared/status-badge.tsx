import { cn } from '@/lib/utils'

type BadgeStatus = 'live' | 'detached' | 'exited' | 'expired' | 'online' | 'offline'

const styleMap: Record<BadgeStatus, string> = {
  live: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/30',
  detached: 'bg-amber-500/10 text-amber-500 border-amber-500/30',
  exited: 'bg-red-500/10 text-red-500 border-red-500/30',
  expired: 'bg-zinc-500/10 text-zinc-400 border-zinc-500/30',
  online: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/30',
  offline: 'bg-zinc-500/10 text-zinc-400 border-zinc-500/30',
}

interface StatusBadgeProps {
  status: BadgeStatus
  label: string
  className?: string
}

export function StatusBadge({ status, label, className }: StatusBadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5 text-xs font-medium',
        styleMap[status],
        className
      )}
    >
      {label}
    </span>
  )
}
