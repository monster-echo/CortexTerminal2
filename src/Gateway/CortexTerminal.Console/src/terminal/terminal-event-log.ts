export type TerminalEventSource = 'xterm' | 'session' | 'gateway'

export interface TerminalEventEntry {
  id: string
  at: string
  source: TerminalEventSource
  message: string
}

export function createTerminalEvent(
  source: TerminalEventSource,
  message: string
): TerminalEventEntry {
  return {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
    at: new Date().toISOString(),
    source,
    message,
  }
}

export function getBootstrapTerminalLogKey(bootstrapId: string) {
  return `bootstrap:${bootstrapId}`
}

export function getSessionTerminalLogKey(sessionId: string) {
  return `session:${sessionId}`
}
