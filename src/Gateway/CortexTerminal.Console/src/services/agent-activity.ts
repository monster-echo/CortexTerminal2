/**
 * Agent activity frame types — mirror CortexTerminal.Contracts.Streaming.AgentActivityFrames
 * on the backend. The Console receives these over the Terminal SignalR connection under the
 * "AgentActivity" event, and replays them from /api/sessions/:id/agent-events on page load.
 *
 * Each frame corresponds to a discrete event in the agent lifecycle (prompt, tool call, stop).
 * The `eventType` discriminator matches the AgentActivityService's TrackedEventTypes list.
 */

export type AgentKindName = 'claude-code' | 'codex' | 'opencode'

export interface AgentStartedFrame {
  sessionId: string
  kind: AgentKindName
  agentSessionId: string | null
  workDir: string | null
}

export interface AgentPromptSubmittedFrame {
  sessionId: string
  promptText: string
  promptId: string | null
}

export interface AgentToolCallFrame {
  sessionId: string
  toolName: string
  input: string | null
  output: string | null
  durationMs: number
  isError: boolean
}

export interface AgentStoppedFrame {
  sessionId: string
  totalCostUsd: number | null
  totalTokensIn: number | null
  totalTokensOut: number | null
  stopReason: string | null
}

export interface AgentSessionEndedFrame {
  sessionId: string
  reason: string | null
}

export interface AgentSubagentStoppedFrame {
  sessionId: string
  subagentId: string | null
}

export interface AgentNotifiedFrame {
  sessionId: string
  title: string | null
  body: string | null
}

export interface AgentCompactingFrame {
  sessionId: string
  trigger: string | null
}

export interface AgentTitleUpdatedFrame {
  sessionId: string
  title: string
}

export type AgentActivityFrame =
  | AgentStartedFrame
  | AgentPromptSubmittedFrame
  | AgentToolCallFrame
  | AgentStoppedFrame
  | AgentSessionEndedFrame
  | AgentSubagentStoppedFrame
  | AgentNotifiedFrame
  | AgentCompactingFrame
  | AgentTitleUpdatedFrame

export type AgentActivityEventType =
  | 'AgentStarted'
  | 'AgentPromptSubmitted'
  | 'AgentToolCall'
  | 'AgentStopped'
  | 'AgentSessionEnded'
  | 'AgentSubagentStopped'
  | 'AgentNotified'
  | 'AgentCompacting'
  | 'AgentTitleUpdated'

export interface AgentActivityEnvelope {
  eventType: AgentActivityEventType
  frame: AgentActivityFrame
}

/**
 * Persisted event row from /api/sessions/:id/agent-events. The payloadJson field is the
 * serialized frame; callers parse it lazily based on eventType.
 */
export interface AgentActivityEntry {
  id: number
  eventType: AgentActivityEventType
  payloadJson: string
  createdAtUtc: string
}

export function parseAgentActivityFrame(
  eventType: AgentActivityEventType,
  payloadJson: string,
): AgentActivityFrame {
  const parsed = JSON.parse(payloadJson) as Record<string, unknown>
  switch (eventType) {
    case 'AgentStarted':
      return {
        sessionId: parsed['sessionId'] as string,
        kind: parsed['kind'] as AgentKindName,
        agentSessionId: (parsed['agentSessionId'] as string | null) ?? null,
        workDir: (parsed['workDir'] as string | null) ?? null,
      }
    case 'AgentPromptSubmitted':
      return {
        sessionId: parsed['sessionId'] as string,
        promptText: (parsed['promptText'] as string) ?? '',
        promptId: (parsed['promptId'] as string | null) ?? null,
      }
    case 'AgentToolCall':
      return {
        sessionId: parsed['sessionId'] as string,
        toolName: (parsed['toolName'] as string) ?? 'unknown',
        input: (parsed['input'] as string | null) ?? null,
        output: (parsed['output'] as string | null) ?? null,
        durationMs: (parsed['durationMs'] as number) ?? 0,
        isError: (parsed['isError'] as boolean) ?? false,
      }
    case 'AgentStopped':
      return {
        sessionId: parsed['sessionId'] as string,
        totalCostUsd: (parsed['totalCostUsd'] as number | null) ?? null,
        totalTokensIn: (parsed['totalTokensIn'] as number | null) ?? null,
        totalTokensOut: (parsed['totalTokensOut'] as number | null) ?? null,
        stopReason: (parsed['stopReason'] as string | null) ?? null,
      }
    case 'AgentSessionEnded':
      return {
        sessionId: parsed['sessionId'] as string,
        reason: (parsed['reason'] as string | null) ?? null,
      }
    case 'AgentSubagentStopped':
      return {
        sessionId: parsed['sessionId'] as string,
        subagentId: (parsed['subagentId'] as string | null) ?? null,
      }
    case 'AgentNotified':
      return {
        sessionId: parsed['sessionId'] as string,
        title: (parsed['title'] as string | null) ?? null,
        body: (parsed['body'] as string | null) ?? null,
      }
    case 'AgentCompacting':
      return {
        sessionId: parsed['sessionId'] as string,
        trigger: (parsed['trigger'] as string | null) ?? null,
      }
    case 'AgentTitleUpdated':
      return {
        sessionId: parsed['sessionId'] as string,
        title: (parsed['title'] as string) ?? '',
      }
  }
}

export function describeAgentKind(kind: string | null | undefined): {
  label: string
  icon: string
} {
  switch (kind) {
    case 'claude-code':
      return { label: 'Claude Code', icon: '🤖' }
    case 'codex':
      return { label: 'Codex', icon: '🟢' }
    case 'opencode':
      return { label: 'OpenCode', icon: '🔵' }
    default:
      return { label: 'Unknown', icon: '❓' }
  }
}

export function sessionDisplayTitle(
  inferredTitle: string | null | undefined,
  sessionId: string,
): string {
  if (inferredTitle && inferredTitle.trim().length > 0) return inferredTitle
  return sessionId
}
