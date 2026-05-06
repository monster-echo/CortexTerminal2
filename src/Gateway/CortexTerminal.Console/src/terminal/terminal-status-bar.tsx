import { useTranslation } from 'react-i18next'
import { TerminalSquare } from 'lucide-react'
import { StatusDot } from '@/components/shared/status-dot'
import type { SessionStatus } from '@/services/console-api'

interface TerminalStatusBarProps {
  status: SessionStatus | 'offline'
  sessionId: string
  workerId?: string
  latencyMs: number | null
  cols: number
  rows: number
  statusMessage?: string | null
}

export function TerminalStatusBar({
  status,
  sessionId,
  workerId,
  latencyMs,
  cols,
  rows,
  statusMessage,
}: TerminalStatusBarProps) {
  const { t } = useTranslation()
  const shortId =
    sessionId.length > 12 ? sessionId.slice(0, 12) : sessionId

  return (
    <div className='flex h-9 shrink-0 items-center justify-between border-t border-border bg-card px-3 text-xs text-muted-foreground'>
      <div className='flex min-w-0 items-center gap-3'>
        <StatusDot status={status === 'offline' ? 'offline' : status} />
        <span className='font-medium'>{status}</span>
        <span className='text-muted-foreground/60'>{shortId}</span>
        {workerId && (
          <span className='max-w-[120px] truncate text-muted-foreground/60 sm:max-w-[200px]'>{workerId}</span>
        )}
        {statusMessage && (
          <>
            <span className='text-muted-foreground/30'>|</span>
            <div className='flex min-w-0 items-center gap-1.5'>
              <TerminalSquare className='size-3 shrink-0' />
              <span className='truncate'>{statusMessage}</span>
            </div>
          </>
        )}
      </div>
      <div className='flex items-center gap-3'>
        {latencyMs !== null && (
          <span>{t('terminal.latency', { ms: Math.round(latencyMs) })}</span>
        )}
        <span>
          {cols}x{rows}
        </span>
      </div>
    </div>
  )
}
