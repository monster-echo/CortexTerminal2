import { Gauge, TerminalSquare } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { useIsMobile } from '@/hooks/use-mobile'
import { Button } from '@/components/ui/button'
import { ScrollArea } from '@/components/ui/scroll-area'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import type { TerminalEventEntry } from './terminal-event-log'

export function TerminalHeaderActions(props: {
  eventEntries: TerminalEventEntry[]
  latencyMs?: number | null
  latencyState?: 'live' | 'measuring' | 'offline'
}) {
  const { t } = useTranslation()
  const isMobile = useIsMobile()
  const {
    eventEntries,
    latencyMs = null,
    latencyState = latencyMs === null ? 'measuring' : 'live',
  } = props

  return (
    <div className='ml-auto flex items-center gap-2'>
      <div
        className={cn(
          'inline-flex h-9 items-center gap-2 rounded-md border px-3 text-xs',
          latencyState === 'live' && 'border-emerald-500/30 bg-emerald-500/8',
          latencyState === 'measuring' && 'bg-muted/60 text-muted-foreground',
          latencyState === 'offline' && 'border-amber-500/30 bg-amber-500/10'
        )}
        >
          <Gauge className='size-4 shrink-0' />
          {!isMobile && (
            <span className='font-medium tracking-wide uppercase'>
              {t('terminal.e2eLatency')}
            </span>
          )}
          <span className='font-mono text-foreground'>
            {formatLatency(t, latencyMs, latencyState)}
          </span>
        </div>

      {!isMobile && (
      <Sheet>
        <SheetTrigger asChild>
          <Button variant='outline' size='sm'>
            <TerminalSquare className='size-4' /> {t('terminal.logs.button')}
          </Button>
        </SheetTrigger>
        <SheetContent side='right' className='flex w-full flex-col sm:max-w-lg'>
            <SheetHeader>
            <SheetTitle>{t('terminal.logs.title')}</SheetTitle>
            <SheetDescription>
              {t('terminal.logs.description')}
            </SheetDescription>
          </SheetHeader>
          <ScrollArea className='min-h-0 flex-1 rounded-md border'>
            <div className='space-y-3 p-4'>
              {eventEntries.length === 0 ? (
                <p className='text-sm text-muted-foreground'>
                  {t('terminal.logs.empty')}
                </p>
              ) : (
                eventEntries.map((event) => (
                  <div
                    key={event.id}
                    className='rounded-lg border bg-card p-3 shadow-xs'
                  >
                    <div className='flex items-center justify-between gap-3'>
                      <span className='rounded bg-muted px-2 py-0.5 text-[11px] font-medium tracking-wide text-muted-foreground uppercase'>
                        {event.source}
                      </span>
                      <span className='text-xs text-muted-foreground'>
                        {formatEventTime(event.at)}
                      </span>
                    </div>
                    <p className='mt-2 text-sm'>{event.message}</p>
                  </div>
                ))
              )}
            </div>
          </ScrollArea>
        </SheetContent>
      </Sheet>
      )}
    </div>
  )
}

function formatLatency(
  t: ReturnType<typeof useTranslation>['t'],
  latencyMs: number | null,
  latencyState: 'live' | 'measuring' | 'offline'
) {
  if (latencyState === 'offline') {
    return t('terminal.offline')
  }

  if (latencyMs === null) {
    return t('terminal.measuringShort')
  }

  return t('terminal.latency', { ms: Math.round(latencyMs) })
}

function formatEventTime(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(value))
}
