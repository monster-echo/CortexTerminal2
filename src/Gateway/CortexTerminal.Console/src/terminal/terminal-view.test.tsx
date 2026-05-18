import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from 'vitest-browser-react'
import { userEvent } from 'vitest/browser'
import { TerminalView } from './terminal-view'
import type {
  TerminalGateway,
  TerminalGatewayConnection,
} from '@/services/terminal-gateway'

const mocks = vi.hoisted(() => ({
  navigate: vi.fn(),
  appendEvent: vi.fn(),
  prune: vi.fn(),
  fit: vi.fn<() => { columns: number; rows: number }>(),
  write: vi.fn<(data: string) => void>(),
  clear: vi.fn<() => void>(),
  resize: vi.fn<() => Promise<void>>(),
  writeInput: vi.fn<() => Promise<void>>(),
  probeLatency: vi.fn<() => Promise<void>>(),
  close: vi.fn<() => Promise<void>>(),
  dispose: vi.fn<() => Promise<void>>(),
}))

vi.mock('@tanstack/react-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@tanstack/react-router')>()
  return {
    ...actual,
    useNavigate: () => mocks.navigate,
  }
})

vi.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key: string) => key,
  }),
}))

vi.mock('@/stores/terminal-event-log-store', () => ({
  useTerminalEventLogStore: (
    selector: (state: {
      appendEvent: typeof mocks.appendEvent
      prune: typeof mocks.prune
    }) => unknown
  ) =>
    selector({
      appendEvent: mocks.appendEvent,
      prune: mocks.prune,
    }),
}))

vi.mock('./terminal-viewport', () => ({
  TerminalViewport: ({
    onReady,
    onResize,
  }: {
    onReady?: (terminal: {
      fit: () => { columns: number; rows: number }
      write: (data: string) => void
      clear: () => void
      dispose: () => void
    }) => void
    onResize?: (size: { columns: number; rows: number }) => void
  }) => (
    <div>
      <button
        type='button'
        onClick={() =>
          onReady?.({
            fit: mocks.fit,
            write: mocks.write,
            clear: mocks.clear,
            dispose: vi.fn(),
          })
        }
      >
        ready
      </button>
      <button
        type='button'
        onClick={() => onResize?.({ columns: 100, rows: 40 })}
      >
        same size
      </button>
      <button
        type='button'
        onClick={() => onResize?.({ columns: 120, rows: 45 })}
      >
        new size
      </button>
    </div>
  ),
}))

vi.mock('./terminal-virtual-keys', () => ({
  TerminalVirtualKeys: () => null,
  applyCtrlModifier: (data: string) => data,
  applyAltModifier: (data: string) => data,
}))

vi.mock('./terminal-status-bar', () => ({
  TerminalStatusBar: () => null,
}))

describe('TerminalView', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.fit.mockReturnValue({ columns: 100, rows: 40 })
    mocks.resize.mockResolvedValue(undefined)
    mocks.writeInput.mockResolvedValue(undefined)
    mocks.probeLatency.mockResolvedValue(undefined)
    mocks.close.mockResolvedValue(undefined)
    mocks.dispose.mockResolvedValue(undefined)
  })

  it('sends resize commands from xterm resize events and skips duplicate sizes', async () => {
    const connection: TerminalGatewayConnection = {
      writeInput: mocks.writeInput,
      resize: mocks.resize,
      probeLatency: mocks.probeLatency,
      close: mocks.close,
      dispose: mocks.dispose,
    }
    const gateway: TerminalGateway = {
      connect: vi.fn().mockResolvedValue(connection),
    }

    const screen = await render(
      <TerminalView gateway={gateway} sessionId='session-1' />
    )

    await userEvent.click(screen.getByRole('button', { name: 'ready' }))
    await vi.waitFor(() => expect(gateway.connect).toHaveBeenCalledOnce())
    expect(mocks.resize).not.toHaveBeenCalled()

    await userEvent.click(screen.getByRole('button', { name: 'same size' }))
    expect(mocks.resize).toHaveBeenCalledTimes(1)
    expect(mocks.resize).toHaveBeenLastCalledWith(100, 40)

    await userEvent.click(screen.getByRole('button', { name: 'new size' }))
    expect(mocks.resize).toHaveBeenCalledTimes(2)
    expect(mocks.resize).toHaveBeenLastCalledWith(120, 45)

    await userEvent.click(screen.getByRole('button', { name: 'same size' }))
    expect(mocks.resize).toHaveBeenCalledTimes(3)
    expect(mocks.resize).toHaveBeenLastCalledWith(100, 40)
  })
})
