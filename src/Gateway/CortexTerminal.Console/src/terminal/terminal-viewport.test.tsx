import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from 'vitest-browser-react'
import { TerminalViewport } from './terminal-viewport'

const mocks = vi.hoisted(() => ({
  fit: vi.fn<() => { columns: number; rows: number }>(),
  dispose: vi.fn(),
  onResizeHandler: undefined as
    | ((size: { columns: number; rows: number }) => void)
    | undefined,
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
  createBrowserTerminal: (
    _element: HTMLElement,
    _onData: (data: string) => void,
    onResize?: (size: { columns: number; rows: number }) => void
  ) => {
    mocks.onResizeHandler = onResize
    return {
      fit: mocks.fit,
      dispose: mocks.dispose,
      write: vi.fn(),
      clear: vi.fn(),
    }
  },
}))

describe('TerminalViewport', () => {
  const originalResizeObserver = globalThis.ResizeObserver

  beforeEach(() => {
    vi.useFakeTimers()
    vi.clearAllMocks()
    MockResizeObserver.instances = []
    mocks.onResizeHandler = undefined
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

  it('debounces resize observer measurements without reporting resize directly', async () => {
    const onResize = vi.fn()
    await render(<TerminalViewport onData={vi.fn()} onResize={onResize} />)

    expect(onResize).not.toHaveBeenCalled()

    MockResizeObserver.instances[0]!.trigger()
    MockResizeObserver.instances[0]!.trigger()
    MockResizeObserver.instances[0]!.trigger()

    expect(mocks.fit).toHaveBeenCalledTimes(1)
    expect(onResize).not.toHaveBeenCalled()

    vi.advanceTimersByTime(149)
    expect(onResize).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(mocks.fit).toHaveBeenCalledTimes(2)
    expect(onResize).not.toHaveBeenCalled()
  })

  it('reports resize only when xterm emits a resize event', async () => {
    const onResize = vi.fn()
    await render(<TerminalViewport onData={vi.fn()} onResize={onResize} />)

    mocks.onResizeHandler?.({ columns: 120, rows: 40 })

    expect(onResize).toHaveBeenCalledWith({ columns: 120, rows: 40 })
  })
})
