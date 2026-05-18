import { beforeEach, describe, expect, it, vi } from 'vitest'
import { Terminal } from '@xterm/xterm'
import { createBrowserTerminal } from './createBrowserTerminal'

const mocks = vi.hoisted(() => ({
  terminal: {
    rows: 24,
    cols: 80,
    loadAddon: vi.fn(),
    open: vi.fn(),
    onData: vi.fn(() => ({ dispose: vi.fn() })),
    onResize: vi.fn(
      (
        _handler: (size: { cols: number; rows: number }) => void
      ): { dispose: () => void } => ({ dispose: vi.fn() })
    ),
    write: vi.fn((_data: string, callback?: () => void) => {
      callback?.()
    }),
    clear: vi.fn(),
    resize: vi.fn(),
    dispose: vi.fn(),
  },
  fitAddon: {
    fit: vi.fn(),
  },
}))

vi.mock('@xterm/xterm', () => ({
  Terminal: vi.fn(function Terminal() {
    return mocks.terminal
  }),
}))

vi.mock('@xterm/addon-fit', () => ({
  FitAddon: vi.fn(function FitAddon() {
    return mocks.fitAddon
  }),
}))

describe('createBrowserTerminal', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.terminal.rows = 24
    mocks.terminal.cols = 80
  })

  it('uses a conservative scrollback default for large terminal histories', () => {
    createBrowserTerminal(document.createElement('div'), vi.fn())

    expect(Terminal).toHaveBeenCalledWith(
      expect.objectContaining({
        scrollback: 1000,
      })
    )
  })

  it('opens the terminal and fits it during initialization', () => {
    const element = document.createElement('div')

    createBrowserTerminal(element, vi.fn())

    expect(mocks.terminal.loadAddon).toHaveBeenCalledOnce()
    expect(mocks.terminal.open).toHaveBeenCalledWith(element)
    expect(mocks.fitAddon.fit).toHaveBeenCalledOnce()
  })

  it('forwards xterm resize events', () => {
    const onResize = vi.fn()
    createBrowserTerminal(document.createElement('div'), vi.fn(), onResize)

    const handler = mocks.terminal.onResize.mock.calls[0]![0]
    handler({ cols: 100, rows: 30 })

    expect(onResize).toHaveBeenCalledWith({ columns: 100, rows: 30 })
  })

  it('fits through the fit addon without manually resizing the terminal', () => {
    const terminal = createBrowserTerminal(document.createElement('div'), vi.fn())
    mocks.terminal.cols = 100
    mocks.terminal.rows = 30

    const size = terminal.fit()

    expect(mocks.fitAddon.fit).toHaveBeenCalledTimes(2)
    expect(mocks.terminal.resize).not.toHaveBeenCalled()
    expect(size).toEqual({ columns: 100, rows: 30 })
  })

  it('writes data using xterm write callbacks', () => {
    const terminal = createBrowserTerminal(document.createElement('div'), vi.fn())

    terminal.write('output')

    expect(mocks.terminal.write).toHaveBeenCalledWith(
      'output',
      expect.any(Function)
    )
  })
})
