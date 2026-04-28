import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  clearPendingSessionCreations,
  getOrStartSessionCreation,
} from './session-bootstrap'

describe('getOrStartSessionCreation', () => {
  afterEach(() => {
    clearPendingSessionCreations()
  })

  it('reuses an in-flight creation for the same bootstrap id', async () => {
    let resolve!: (value: { sessionId: string }) => void
    const createSession = vi.fn(
      () =>
        new Promise<{ sessionId: string }>((nextResolve) => {
          resolve = nextResolve
        })
    )

    const first = getOrStartSessionCreation('boot-1', createSession)
    const second = getOrStartSessionCreation('boot-1', createSession)

    expect(first).toBe(second)
    expect(createSession).toHaveBeenCalledTimes(1)

    resolve({ sessionId: 'sess-1' })

    await expect(first).resolves.toEqual({ sessionId: 'sess-1' })
  })

  it('starts a new creation after the previous one settles', async () => {
    const createSession = vi
      .fn<() => Promise<{ sessionId: string }>>()
      .mockResolvedValueOnce({ sessionId: 'sess-1' })
      .mockResolvedValueOnce({ sessionId: 'sess-2' })

    await expect(
      getOrStartSessionCreation('boot-2', createSession)
    ).resolves.toEqual({ sessionId: 'sess-1' })

    await expect(
      getOrStartSessionCreation('boot-2', createSession)
    ).resolves.toEqual({ sessionId: 'sess-2' })

    expect(createSession).toHaveBeenCalledTimes(2)
  })
})
