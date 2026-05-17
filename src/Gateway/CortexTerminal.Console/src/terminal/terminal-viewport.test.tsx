import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from 'vitest-browser-react'
import { TerminalViewport } from './terminal-viewport'

const mocks = vi.hoisted(() => ({
  fit: vi.fn<() => { columns: number; rows: number }>(),
  dispose: vi.fn(),
}))

class MockResizeObserver {
  static instances: MockResizeObserver[] = []
  private callback: ResizeObserverCallback

  constructor(callback: ResizeObserverCallback) {
    this.callback = callback
    MockResizeObserver.instances.push(this)
  }

  observe = vi.fn()
  disconnect = vi.fn()

  trigger() {
    this.callback([], this as unknown as ResizeObserver)
  }
}

vi.mock('./createBrowserTerminal', () => ({
  createBrowserTerminal: () => ({
    fit: mocks.fit,
    dispose: mocks.dispose,
    write: vi.fn(),
    clear: vi.fn(),
  }),
}))

describe('TerminalViewport', () => {
  const originalResizeObserver = globalThis.ResizeObserver

  beforeEach(() => {
    vi.useFakeTimers()
    vi.clearAllMocks()
    MockResizeObserver.instances = []
    globalThis.ResizeObserver =
      MockResizeObserver as unknown as typeof ResizeObserver
    mocks.fit
      .mockReturnValueOnce({ columns: 80, rows: 24 })
      .mockReturnValueOnce({ columns: 120, rows: 40 })
  })

  afterEach(() => {
    vi.useRealTimers()
    globalThis.ResizeObserver = originalResizeObserver
  })

  it('debounces resize observer measurements and reports only the final size', async () => {
    const onResize = vi.fn()
    await render(<TerminalViewport onData={vi.fn()} onResize={onResize} />)

    expect(onResize).toHaveBeenCalledOnce()
    expect(onResize).toHaveBeenLastCalledWith({ columns: 80, rows: 24 })

    MockResizeObserver.instances[0]!.trigger()
    MockResizeObserver.instances[0]!.trigger()
    MockResizeObserver.instances[0]!.trigger()

    expect(mocks.fit).toHaveBeenCalledTimes(1)
    expect(onResize).toHaveBeenCalledTimes(1)

    vi.advanceTimersByTime(149)
    expect(onResize).toHaveBeenCalledTimes(1)

    vi.advanceTimersByTime(1)
    expect(mocks.fit).toHaveBeenCalledTimes(2)
    expect(onResize).toHaveBeenCalledTimes(2)
    expect(onResize).toHaveBeenLastCalledWith({ columns: 120, rows: 40 })
  })
})
