import { useMemo, useState } from 'react'
import { Bell, FileText, Loader2, LogOut, MessageSquare, Play, Square, Users, Wrench } from 'lucide-react'
import { useTranslation } from 'react-i18next'
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
import {
  describeAgentKind,
  type AgentActivityEnvelope,
  type AgentActivityEventType,
  type AgentKindName,
} from '@/services/agent-activity'
import type { AgentActivityTimelineEntry } from './use-agent-activity'

export function AgentActivitySheet(props: {
  sessionId: string
  timeline: AgentActivityTimelineEntry[]
  isLoading: boolean
  error: unknown
}) {
  const { sessionId, timeline, isLoading, error } = props
  const { t } = useTranslation()
  const [open, setOpen] = useState(false)

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button variant='outline' size='sm'>
          <Wrench className='size-4' />
          {t('terminal.agentActivity.button')}
        </Button>
      </SheetTrigger>
      <SheetContent side='right' className='flex w-full flex-col sm:max-w-lg'>
        <SheetHeader>
          <SheetTitle>{t('terminal.agentActivity.title')}</SheetTitle>
          <SheetDescription>
            {t('terminal.agentActivity.description')}
          </SheetDescription>
        </SheetHeader>

        <ScrollArea className='min-h-0 flex-1'>
          <div className='space-y-3 p-4'>
            {isLoading && timeline.length === 0 && (
              <div className='flex items-center justify-center py-12 text-muted-foreground'>
                <Loader2 className='mr-2 size-4 animate-spin' />
                {t('common.loading')}
              </div>
            )}

            {error ? (
              <div className='py-12 text-center text-sm text-destructive'>
                {error instanceof Error ? error.message : t('common.error')}
              </div>
            ) : null}

            {!isLoading && timeline.length === 0 && !error && (
              <div className='py-12 text-center text-sm text-muted-foreground'>
                {t('terminal.agentActivity.empty')}
              </div>
            )}

            {sessionId && timeline.length > 0 && (
              <div className='space-y-3'>
                {timeline.map((entry) => (
                  <AgentActivityCard key={entry.id} entry={entry} />
                ))}
              </div>
            )}
          </div>
        </ScrollArea>
      </SheetContent>
    </Sheet>
  )
}

function AgentActivityCard(props: { entry: AgentActivityTimelineEntry }) {
  const { entry } = props
  const { t } = useTranslation()
  const [expanded, setExpanded] = useState(false)

  const icon = useMemo(() => iconFor(entry.eventType), [entry.eventType])
  const receivedAt = useMemo(
    () => formatTimestamp(entry.receivedAtUtc),
    [entry.receivedAtUtc]
  )

  const frame = entry.envelope.frame
  const hasDetail =
    entry.eventType === 'AgentToolCall' ||
    entry.eventType === 'AgentPromptSubmitted'

  return (
    <div className='rounded-lg border bg-card p-3 text-sm shadow-sm'>
      <div className='flex items-start gap-3'>
        <span className='mt-0.5 text-muted-foreground'>{icon}</span>
        <div className='min-w-0 flex-1'>
          <div className='flex items-baseline justify-between gap-2'>
            <span className='truncate font-medium'>
              {titleFor(entry.eventType, frame, t)}
            </span>
            <span className='shrink-0 text-xs text-muted-foreground'>
              {receivedAt}
            </span>
          </div>
          {entry.eventType === 'AgentStarted' && (
            <AgentStartedDetails
              kind={(frame as { kind?: AgentKindName }).kind ?? 'claude-code'}
              workDir={(frame as { workDir?: string | null }).workDir ?? null}
              agentSessionId={
                (frame as { agentSessionId?: string | null }).agentSessionId ??
                null
              }
            />
          )}
          {entry.eventType === 'AgentStopped' && (
            <AgentStoppedDetails
              totalCostUsd={
                (frame as { totalCostUsd?: number | null }).totalCostUsd ?? null
              }
              totalTokensIn={
                (frame as { totalTokensIn?: number | null }).totalTokensIn ??
                null
              }
              totalTokensOut={
                (frame as { totalTokensOut?: number | null }).totalTokensOut ??
                null
              }
              stopReason={
                (frame as { stopReason?: string | null }).stopReason ?? null
              }
            />
          )}
          {entry.eventType === 'AgentNotified' && (
            <AgentNotifiedDetails
              title={(frame as { title?: string | null }).title ?? null}
              body={(frame as { body?: string | null }).body ?? null}
            />
          )}
          {hasDetail && (
            <button
              type='button'
              className='mt-1 text-xs text-primary hover:underline'
              onClick={() => setExpanded((v) => !v)}
            >
              {expanded
                ? t('terminal.agentActivity.collapse')
                : t('terminal.agentActivity.expand')}
            </button>
          )}
          {expanded && entry.eventType === 'AgentPromptSubmitted' && (
            <pre className='mt-2 max-h-48 overflow-auto whitespace-pre-wrap rounded bg-muted p-2 text-xs'>
              {(frame as { promptText?: string }).promptText ?? ''}
            </pre>
          )}
          {expanded && entry.eventType === 'AgentToolCall' && (
            <ToolCallDetails
              toolName={(frame as { toolName?: string }).toolName ?? 'unknown'}
              input={(frame as { input?: string | null }).input ?? null}
              output={(frame as { output?: string | null }).output ?? null}
              durationMs={(frame as { durationMs?: number }).durationMs ?? 0}
              isError={(frame as { isError?: boolean }).isError ?? false}
            />
          )}
        </div>
      </div>
    </div>
  )
}

function AgentStartedDetails(props: {
  kind: AgentKindName
  workDir: string | null
  agentSessionId: string | null
}) {
  const { kind, workDir, agentSessionId } = props
  const meta = describeAgentKind(kind)
  return (
    <div className='mt-1 space-y-0.5 text-xs text-muted-foreground'>
      <div>
        {meta.icon} {meta.label}
        {agentSessionId ? ` · ${agentSessionId.slice(0, 8)}` : ''}
      </div>
      {workDir && <div className='truncate'>📁 {workDir}</div>}
    </div>
  )
}

function AgentStoppedDetails(props: {
  totalCostUsd: number | null
  totalTokensIn: number | null
  totalTokensOut: number | null
  stopReason: string | null
}) {
  const { totalCostUsd, totalTokensIn, totalTokensOut, stopReason } = props
  return (
    <div className='mt-1 space-y-0.5 text-xs text-muted-foreground'>
      {totalCostUsd !== null && <div>💵 ${totalCostUsd.toFixed(4)}</div>}
      {totalTokensIn !== null && totalTokensOut !== null && (
        <div>
          🔢 {totalTokensIn.toLocaleString()} in ·{' '}
          {totalTokensOut.toLocaleString()} out
        </div>
      )}
      {stopReason && <div>🛑 {stopReason}</div>}
    </div>
  )
}

function AgentNotifiedDetails(props: {
  title: string | null
  body: string | null
}) {
  const { title, body } = props
  if (!title && !body) return null
  return (
    <div className='mt-1 space-y-0.5 text-xs text-muted-foreground'>
      {title && <div className='font-medium'>{title}</div>}
      {body && <div>{body}</div>}
    </div>
  )
}

function ToolCallDetails(props: {
  toolName: string
  input: string | null
  output: string | null
  durationMs: number
  isError: boolean
}) {
  const { toolName, input, output, durationMs, isError } = props
  return (
    <div className='mt-2 space-y-2 text-xs'>
      <div className='flex flex-wrap items-center gap-2'>
        <span className='rounded bg-muted px-1.5 py-0.5 font-mono'>
          {toolName}
        </span>
        <span
          className={isError ? 'text-destructive' : 'text-muted-foreground'}
        >
          {durationMs} ms{isError ? ' · error' : ''}
        </span>
      </div>
      {input && (
        <div>
          <div className='text-muted-foreground'>Input</div>
          <pre className='max-h-48 overflow-auto whitespace-pre-wrap rounded bg-muted p-2'>
            {input}
          </pre>
        </div>
      )}
      {output && (
        <div>
          <div className='text-muted-foreground'>Output</div>
          <pre className='max-h-48 overflow-auto whitespace-pre-wrap rounded bg-muted p-2'>
            {output}
          </pre>
        </div>
      )}
    </div>
  )
}

function iconFor(eventType: AgentActivityEventType) {
  switch (eventType) {
    case 'AgentStarted':
      return <Play className='size-4' />
    case 'AgentPromptSubmitted':
      return <MessageSquare className='size-4' />
    case 'AgentToolCall':
      return <Wrench className='size-4' />
    case 'AgentStopped':
      return <Square className='size-4' />
    case 'AgentSessionEnded':
      return <LogOut className='size-4' />
    case 'AgentSubagentStopped':
      return <Users className='size-4' />
    case 'AgentNotified':
      return <Bell className='size-4' />
    case 'AgentCompacting':
      return <FileText className='size-4' />
  }
}

function titleFor(
  eventType: AgentActivityEventType,
  frame: AgentActivityEnvelope['frame'],
  t: (key: string) => string
): string {
  switch (eventType) {
    case 'AgentStarted':
      return t('terminal.agentActivity.started')
    case 'AgentPromptSubmitted':
      return t('terminal.agentActivity.promptSubmitted')
    case 'AgentToolCall': {
      const toolName = (frame as { toolName?: string }).toolName ?? 'unknown'
      return t('terminal.agentActivity.toolCall').replace('{tool}', toolName)
    }
    case 'AgentStopped':
      return t('terminal.agentActivity.stopped')
    case 'AgentSessionEnded':
      return t('terminal.agentActivity.sessionEnded')
    case 'AgentSubagentStopped':
      return t('terminal.agentActivity.subagentStopped')
    case 'AgentNotified':
      return t('terminal.agentActivity.notified')
    case 'AgentCompacting':
      return t('terminal.agentActivity.compacting')
  }
}

function formatTimestamp(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(date)
}
