import type { ReactNode } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from 'vitest-browser-react'
import { userEvent } from 'vitest/browser'
import { NewSessionPage } from './new-session-page'

const mocks = vi.hoisted(() => ({
  navigate: vi.fn(),
  createSession:
    vi.fn<
      (size?: {
        columns: number
        rows: number
      }) => Promise<{ sessionId: string }>
    >(),
  appendEvent: vi.fn(),
  moveScope: vi.fn(),
  prune: vi.fn(),
  reset: vi.fn(),
}))

vi.mock('@tanstack/react-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@tanstack/react-router')>()
  return {
    ...actual,
    Link: ({ children }: { children: ReactNode }) => <a>{children}</a>,
    useNavigate: () => mocks.navigate,
  }
})

vi.mock('@/services/console-api', () => ({
  createConsoleApi: () => ({
    createSession: mocks.createSession,
  }),
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: {
    getState: () => ({
      auth: {
        accessToken: 'token',
        reset: mocks.reset,
      },
    }),
  },
}))

vi.mock('@/stores/terminal-event-log-store', () => ({
  useTerminalEventLogStore: (
    selector: (state: {
      logsByScope: Record<string, never[]>
      appendEvent: typeof mocks.appendEvent
      moveScope: typeof mocks.moveScope
      prune: typeof mocks.prune
    }) => unknown
  ) =>
    selector({
      logsByScope: {},
      appendEvent: mocks.appendEvent,
      moveScope: mocks.moveScope,
      prune: mocks.prune,
    }),
}))

vi.mock('@/components/layout/header', () => ({
  Header: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}))

vi.mock('@/components/layout/main', () => ({
  Main: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}))

vi.mock('@/components/ui/button', () => ({
  Button: ({
    children,
    ...props
  }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
    <button {...props}>{children}</button>
  ),
}))

vi.mock('@/terminal/terminal-viewport', () => ({
  TerminalViewport: ({
    onResize,
  }: {
    onResize?: (size: { columns: number; rows: number }) => void
  }) => (
    <div>
      <button onClick={() => onResize?.({ columns: 175, rows: 43 })}>
        measure once
      </button>
      <button onClick={() => onResize?.({ columns: 180, rows: 44 })}>
        measure twice
      </button>
    </div>
  ),
}))

describe('NewSessionPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('keeps the creating status visible while session creation is pending', async () => {
    mocks.createSession.mockImplementation(
      () => new Promise<{ sessionId: string }>(() => undefined)
    )

    const screen = await render(<NewSessionPage bootstrapId='boot-1' />)

    await userEvent.click(screen.getByRole('button', { name: 'measure once' }))

    await vi.waitFor(() =>
      expect(mocks.createSession).toHaveBeenCalledTimes(1)
    )
    expect(mocks.appendEvent).toHaveBeenCalledWith(
      expect.any(String),
      'gateway',
      'Creating session with measured size 175x43.'
    )

    await userEvent.click(screen.getByRole('button', { name: 'measure twice' }))

    // Second resize should not trigger another creation
    expect(mocks.createSession).toHaveBeenCalledTimes(1)
  })
})
