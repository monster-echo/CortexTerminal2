import { useCallback, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'
import {
  type AgentActivityEnvelope,
  type AgentActivityEntry,
  parseAgentActivityFrame,
} from '@/services/agent-activity'

/**
 * Live + replayed agent activity for a session. Returns a merged timeline built from:
 *
 *  - persisted events loaded from /api/sessions/:id/agent-events (initial mount)
 *  - live AgentActivity SignalR frames received while the consumer is mounted
 *
 * Entries dedupe by id (persisted rows use the database identity, live frames get synthetic
 * ids prefixed with `live-` so they don't collide with rows that land in a subsequent replay).
 */
export interface AgentActivityTimelineEntry {
  id: string
  eventType: AgentActivityEnvelope['eventType']
  receivedAtUtc: string
  envelope: AgentActivityEnvelope
}

export function useAgentActivity(sessionId: string | undefined) {
  const [live, setLive] = useState<AgentActivityTimelineEntry[]>([])
  const [trackedSessionId, setTrackedSessionId] = useState(sessionId)

  // Reset live entries whenever we switch sessions so the next mount starts clean.
  // Done in render (not an effect) to avoid cascading renders.
  if (trackedSessionId !== sessionId) {
    setTrackedSessionId(sessionId)
    setLive([])
  }

  const persistedQuery = useQuery({
    queryKey: ['agent-activity', sessionId],
    queryFn: async () => {
      if (!sessionId) return [] as AgentActivityEntry[]
      return getApi().listAgentEvents(sessionId)
    },
    enabled: Boolean(sessionId),
    staleTime: 30_000,
  })

  const pushLive = useCallback((envelope: AgentActivityEnvelope) => {
    setLive((prev) => [
      ...prev,
      {
        id: `live-${prev.length + 1}`,
        eventType: envelope.eventType,
        receivedAtUtc: new Date().toISOString(),
        envelope,
      },
    ])
  }, [])

  const persisted: AgentActivityTimelineEntry[] = (persistedQuery.data ?? []).map(
    (row) => ({
      id: `db-${row.id}`,
      eventType: row.eventType,
      receivedAtUtc: row.createdAtUtc,
      envelope: {
        eventType: row.eventType,
        frame: parseAgentActivityFrame(row.eventType, row.payloadJson),
      },
    })
  )

  const timeline = [...persisted, ...live]

  return {
    timeline,
    isLoading: persistedQuery.isLoading,
    error: persistedQuery.error,
    pushLive,
  }
}
