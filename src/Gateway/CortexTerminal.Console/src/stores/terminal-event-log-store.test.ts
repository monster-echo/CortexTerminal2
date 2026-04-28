import {
  getBootstrapTerminalLogKey,
  getSessionTerminalLogKey,
} from '@/terminal/terminal-event-log'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const STORAGE_KEY = 'cortex_terminal_event_logs'

async function importTerminalEventLogStore() {
  const { useTerminalEventLogStore } =
    await import('./terminal-event-log-store')
  return useTerminalEventLogStore
}

describe('useTerminalEventLogStore', () => {
  beforeEach(() => {
    localStorage.removeItem(STORAGE_KEY)
    vi.resetModules()
    vi.useRealTimers()
  })

  it('starts empty when no terminal logs are persisted', async () => {
    const useTerminalEventLogStore = await importTerminalEventLogStore()

    expect(useTerminalEventLogStore.getState().logsByScope).toEqual({})
  })

  it('persists appended events across store reloads', async () => {
    const useTerminalEventLogStore = await importTerminalEventLogStore()
    const scopeKey = getSessionTerminalLogKey('session-123')

    useTerminalEventLogStore
      .getState()
      .appendEvent(scopeKey, 'gateway', 'Transport connected.')

    vi.resetModules()
    const useTerminalEventLogStoreAfterReload =
      await importTerminalEventLogStore()

    expect(
      useTerminalEventLogStoreAfterReload.getState().logsByScope[scopeKey]?.[0]
        ?.message
    ).toBe('Transport connected.')
  })

  it('moves bootstrap logs onto the created session scope', async () => {
    const useTerminalEventLogStore = await importTerminalEventLogStore()
    const bootstrapKey = getBootstrapTerminalLogKey('bootstrap-1')
    const sessionKey = getSessionTerminalLogKey('session-1')

    useTerminalEventLogStore
      .getState()
      .appendEvent(bootstrapKey, 'gateway', 'Creating session...')
    useTerminalEventLogStore
      .getState()
      .appendEvent(sessionKey, 'gateway', 'Connecting to session session-1.')

    useTerminalEventLogStore.getState().moveScope(bootstrapKey, sessionKey)

    const logsByScope = useTerminalEventLogStore.getState().logsByScope
    expect(logsByScope[bootstrapKey]).toBeUndefined()
    expect(logsByScope[sessionKey]?.map((entry) => entry.message)).toEqual([
      'Creating session...',
      'Connecting to session session-1.',
    ])
  })

  it('prunes expired events when requested', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-04-24T10:00:00.000Z'))

    const useTerminalEventLogStore = await importTerminalEventLogStore()
    const sessionKey = getSessionTerminalLogKey('session-expiring')

    useTerminalEventLogStore
      .getState()
      .appendEvent(sessionKey, 'gateway', 'Old event')

    vi.setSystemTime(new Date('2026-04-25T11:00:00.000Z'))
    useTerminalEventLogStore.getState().prune()

    expect(
      useTerminalEventLogStore.getState().logsByScope[sessionKey]
    ).toBeUndefined()
  })
})
