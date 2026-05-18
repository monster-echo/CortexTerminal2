import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createDebouncedAction } from './debounce'

describe('createDebouncedAction', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('runs only the final scheduled action', () => {
    const callback = vi.fn()
    const action = createDebouncedAction(callback, 150)

    action()
    action()
    action()

    vi.advanceTimersByTime(149)
    expect(callback).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(callback).toHaveBeenCalledOnce()
  })

  it('cancels a pending action', () => {
    const callback = vi.fn()
    const action = createDebouncedAction(callback, 150)

    action()
    action.cancel()
    vi.advanceTimersByTime(150)

    expect(callback).not.toHaveBeenCalled()
  })

  it('can be scheduled again after running', () => {
    const callback = vi.fn()
    const action = createDebouncedAction(callback, 150)

    action()
    vi.advanceTimersByTime(150)
    action()
    vi.advanceTimersByTime(150)

    expect(callback).toHaveBeenCalledTimes(2)
  })
})
