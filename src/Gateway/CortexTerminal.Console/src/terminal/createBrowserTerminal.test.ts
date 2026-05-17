import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createBrowserTerminal } from './createBrowserTerminal'

const mocks = vi.hoisted(() => ({
  terminal: {
    buffer: {
      active: {
        viewportY: 0,
        baseY: 0,
      },
    },
    rows: 24,
    cols: 80,
    loadAddon: vi.fn(),
    open: vi.fn(),
    onData: vi.fn(() => ({ dispose: vi.fn() })),
    write: vi.fn(),
    clear: vi.fn(),
    resize: vi.fn((cols: number, rows: number) => {
      mocks.terminal.cols = cols
      mocks.terminal.rows = rows
    }),
    scrollToBottom: vi.fn(),
    dispose: vi.fn(),
  },
  fitAddon: {
    fit: vi.fn(),
    proposeDimensions: vi.fn<() => { cols: number; rows: number } | undefined>(),
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
    vi.useFakeTimers()
    vi.clearAllMocks()
    mocks.terminal.buffer.active.viewportY = 76
    mocks.terminal.buffer.active.baseY = 100
    mocks.terminal.rows = 24
    mocks.terminal.cols = 80
    mocks.fitAddon.proposeDimensions.mockReturnValue({ cols: 100, rows: 30 })
  })

  it('keeps the terminal anchored to the bottom after resizing from the bottom', () => {
    const terminal = createBrowserTerminal(document.createElement('div'), vi.fn())

    terminal.fit()

    expect(mocks.terminal.resize).toHaveBeenCalledWith(100, 30)
    expect(mocks.terminal.scrollToBottom).toHaveBeenCalledTimes(1)

    vi.runOnlyPendingTimers()

    expect(mocks.terminal.scrollToBottom).toHaveBeenCalledTimes(2)
  })

  it('does not force bottom scroll when the user is viewing scrollback history', () => {
    mocks.terminal.buffer.active.viewportY = 10
    const terminal = createBrowserTerminal(document.createElement('div'), vi.fn())

    terminal.fit()
    vi.runOnlyPendingTimers()

    expect(mocks.terminal.resize).toHaveBeenCalledWith(100, 30)
    expect(mocks.terminal.scrollToBottom).not.toHaveBeenCalled()
  })

  it('does not resize or scroll when the proposed dimensions are unchanged', () => {
    mocks.fitAddon.proposeDimensions.mockReturnValue({ cols: 80, rows: 24 })
    const terminal = createBrowserTerminal(document.createElement('div'), vi.fn())

    terminal.fit()
    vi.runOnlyPendingTimers()

    expect(mocks.terminal.resize).not.toHaveBeenCalled()
    expect(mocks.terminal.scrollToBottom).not.toHaveBeenCalled()
  })
})
