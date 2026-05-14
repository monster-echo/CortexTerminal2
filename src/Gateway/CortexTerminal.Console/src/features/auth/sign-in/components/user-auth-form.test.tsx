import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, type RenderResult } from 'vitest-browser-react'
import { type Locator, userEvent } from 'vitest/browser'
import { UserAuthForm } from './user-auth-form'

// Mock i18next so t() returns the key (matches how the component renders without a real i18n instance)
vi.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key: string, params?: Record<string, string>) => {
      if (key === 'auth.signInWith' && params?.provider) return `Sign in with ${params.provider}`
      return key
    },
    i18n: { changeLanguage: vi.fn() },
  }),
}))

const FORM_MESSAGES = {
  usernameEmpty: 'auth.validation.usernameRequired',
  passwordEmpty: 'auth.validation.passwordRequired',
} as const

const navigate = vi.fn()
const setUserMock = vi.fn()
const setAccessTokenMock = vi.fn()
const authMocks = vi.hoisted(() => ({
  loginMock: vi.fn(),
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: () => ({
    auth: {
      setUser: setUserMock,
      setAccessToken: setAccessTokenMock,
    },
  }),
}))

vi.mock('@/services/console-api', () => ({
  createConsoleApi: () => ({
    login: authMocks.loginMock,
  }),
}))

vi.mock('@tanstack/react-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@tanstack/react-router')>()
  return {
    ...actual,
    useNavigate: () => navigate,
    Link: ({
      children,
      to,
      className,
      ...rest
    }: {
      children?: React.ReactNode
      to: string
      className?: string
    }) => (
      <a href={to} className={className} {...rest}>
        {children}
      </a>
    ),
  }
})

describe('UserAuthForm', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubEnv('VITE_AUTH_MODE', 'dev')
    authMocks.loginMock.mockResolvedValue({
      token: 'gateway-token',
      username: 'echo',
    })
  })

  describe('Rendering without redirectTo', () => {
    let screen: RenderResult
    let usernameInput: Locator
    let passwordInput: Locator
    let signInButton: Locator

    beforeEach(async () => {
      screen = await render(<UserAuthForm />)
      usernameInput = screen.getByPlaceholder('auth.username')
      passwordInput = screen.getByPlaceholder('auth.password')
      signInButton = screen.getByRole('button', {
        name: 'auth.signIn',
      })
    })

    it('renders username, password fields and submit button', async () => {
      await expect.element(usernameInput).toBeInTheDocument()
      await expect.element(passwordInput).toBeInTheDocument()
      await expect.element(signInButton).toBeInTheDocument()
    })

    it('shows validation messages when submitting empty form', async () => {
      await userEvent.click(signInButton)

      await expect
        .element(screen.getByText(FORM_MESSAGES.usernameEmpty))
        .toBeInTheDocument()
      await expect
        .element(screen.getByText(FORM_MESSAGES.passwordEmpty))
        .toBeInTheDocument()
    })

    it('authenticates and navigates to default route on success', async () => {
      await userEvent.fill(usernameInput, 'echo')
      await userEvent.fill(passwordInput, 'any-password')

      await userEvent.click(signInButton)

      await vi.waitFor(() => expect(authMocks.loginMock).toHaveBeenCalledOnce())
      expect(authMocks.loginMock).toHaveBeenCalledWith('echo', 'any-password')
      expect(setUserMock).toHaveBeenCalledWith({ username: 'echo' })
      expect(setAccessTokenMock).toHaveBeenCalledOnce()
      expect(setAccessTokenMock).toHaveBeenCalledWith('gateway-token')

      await vi.waitFor(() =>
        expect(navigate).toHaveBeenCalledWith({
          to: '/dashboard',
          replace: true,
        })
      )
    })
  })

  it('navigates to redirectTo when provided', async () => {
    const screen = await render(<UserAuthForm redirectTo='/settings' />)

    await userEvent.fill(screen.getByPlaceholder('auth.username'), 'echo')
    await userEvent.fill(screen.getByPlaceholder('auth.password'), 'any-password')

    await userEvent.click(screen.getByRole('button', { name: 'auth.signIn' }))

    await vi.waitFor(() => expect(authMocks.loginMock).toHaveBeenCalledOnce())
    expect(setAccessTokenMock).toHaveBeenCalledOnce()

    await vi.waitFor(() =>
      expect(navigate).toHaveBeenCalledWith({
        to: '/settings',
        replace: true,
      })
    )
  })

  it('does not navigate when login fails', async () => {
    authMocks.loginMock.mockRejectedValue(new Error('Login failed.'))

    const screen = await render(<UserAuthForm />)

    await userEvent.fill(screen.getByPlaceholder('auth.username'), 'echo')
    await userEvent.fill(screen.getByPlaceholder('auth.password'), 'any-password')
    await userEvent.click(screen.getByRole('button', { name: 'auth.signIn' }))

    await vi.waitFor(() => expect(authMocks.loginMock).toHaveBeenCalledOnce())
    expect(setUserMock).not.toHaveBeenCalled()
    expect(setAccessTokenMock).not.toHaveBeenCalled()
    expect(navigate).not.toHaveBeenCalled()
  })
})
