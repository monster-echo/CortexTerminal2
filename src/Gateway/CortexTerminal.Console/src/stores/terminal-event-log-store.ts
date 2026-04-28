import {
  createTerminalEvent,
  type TerminalEventEntry,
  type TerminalEventSource,
} from '@/terminal/terminal-event-log'
import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'

const STORAGE_KEY = 'cortex_terminal_event_logs'
const MAX_EVENTS_PER_SCOPE = 100
const MAX_SCOPES = 20
const LOG_TTL_MS = 1000 * 60 * 60 * 24

interface TerminalEventLogState {
  logsByScope: Record<string, TerminalEventEntry[]>
  appendEvent: (
    scopeKey: string,
    source: TerminalEventSource,
    message: string
  ) => void
  moveScope: (fromScopeKey: string, toScopeKey: string) => void
  clearScope: (scopeKey: string) => void
  prune: () => void
}

export const useTerminalEventLogStore = create<TerminalEventLogState>()(
  persist(
    (set) => ({
      logsByScope: {},
      appendEvent: (scopeKey, source, message) =>
        set((state) => {
          const nextLogsByScope = pruneLogsByScope({
            ...state.logsByScope,
            [scopeKey]: [
              ...(state.logsByScope[scopeKey] ?? []),
              createTerminalEvent(source, message),
            ].slice(-MAX_EVENTS_PER_SCOPE),
          })

          return { logsByScope: nextLogsByScope }
        }),
      moveScope: (fromScopeKey, toScopeKey) =>
        set((state) => {
          if (fromScopeKey === toScopeKey) {
            return { logsByScope: pruneLogsByScope(state.logsByScope) }
          }

          const fromEntries = state.logsByScope[fromScopeKey] ?? []
          const toEntries = state.logsByScope[toScopeKey] ?? []

          const mergedEntries = [...toEntries, ...fromEntries]
            .sort((left, right) => left.at.localeCompare(right.at))
            .slice(-MAX_EVENTS_PER_SCOPE)

          const nextLogsByScope = { ...state.logsByScope }
          delete nextLogsByScope[fromScopeKey]

          if (mergedEntries.length > 0) {
            nextLogsByScope[toScopeKey] = mergedEntries
          }

          return { logsByScope: pruneLogsByScope(nextLogsByScope) }
        }),
      clearScope: (scopeKey) =>
        set((state) => {
          const nextLogsByScope = { ...state.logsByScope }
          delete nextLogsByScope[scopeKey]

          return { logsByScope: nextLogsByScope }
        }),
      prune: () =>
        set((state) => ({
          logsByScope: pruneLogsByScope(state.logsByScope),
        })),
    }),
    {
      name: STORAGE_KEY,
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        logsByScope: pruneLogsByScope(state.logsByScope),
      }),
      merge: (persistedState, currentState) => {
        const nextState = persistedState as
          | Partial<TerminalEventLogState>
          | undefined

        return {
          ...currentState,
          logsByScope: pruneLogsByScope(nextState?.logsByScope ?? {}),
        }
      },
      version: 1,
    }
  )
)

function pruneLogsByScope(logsByScope: Record<string, TerminalEventEntry[]>) {
  const cutoff = Date.now() - LOG_TTL_MS
  const normalizedEntries = Object.entries(logsByScope)
    .map(([scopeKey, entries]) => {
      const nextEntries = entries
        .filter((entry) => Date.parse(entry.at) >= cutoff)
        .slice(-MAX_EVENTS_PER_SCOPE)

      return [scopeKey, nextEntries] as const
    })
    .filter(([, entries]) => entries.length > 0)
    .sort((left, right) => {
      const leftAt = left[1][left[1].length - 1]?.at ?? ''
      const rightAt = right[1][right[1].length - 1]?.at ?? ''
      return rightAt.localeCompare(leftAt)
    })
    .slice(0, MAX_SCOPES)

  return Object.fromEntries(normalizedEntries)
}
