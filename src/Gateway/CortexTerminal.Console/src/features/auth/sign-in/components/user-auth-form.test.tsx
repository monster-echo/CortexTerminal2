import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, type RenderResult } from 'vitest-browser-react'
import { type Locator, userEvent } from 'vitest/browser'
import { UserAuthForm } from './user-auth-form'

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
const mockFetch = vi.hoisted(() => vi.fn())

vi.stubGlobal('fetch', mockFetch)

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: () => ({
    auth: {
      setUser: setUserMock,
      setAccessToken: setAccessTokenMock,
    },
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

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

describe('UserAuthForm', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockFetch.mockReset()
  })

  describe('Password login', () => {
    let screen: RenderResult
    let usernameInput: Locator
    let passwordInput: Locator
    let signInButton: Locator

    beforeEach(async () => {
      mockFetch.mockResolvedValue(
        jsonResponse({ accessToken: 'gateway-token', username: 'echo' })
      )
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

      await vi.waitFor(() => expect(mockFetch).toHaveBeenCalledOnce())
      expect(mockFetch).toHaveBeenCalledWith(
        '/api/auth/password/login',
        expect.objectContaining({ method: 'POST' })
      )
      expect(setUserMock).toHaveBeenCalledWith({ username: 'echo' })
      expect(setAccessTokenMock).toHaveBeenCalledWith('gateway-token')

      await vi.waitFor(() =>
        expect(navigate).toHaveBeenCalledWith({
          to: '/dashboard',
          replace: true,
        })
      )
    })

    it('opens captcha dialog on CAPTCHA_REQUIRED', async () => {
      mockFetch.mockResolvedValueOnce(
        jsonResponse({ error: 'CAPTCHA_REQUIRED' }, 403)
      )
      // Challenge call for the captcha dialog
      mockFetch.mockResolvedValueOnce(
        jsonResponse({
          id: 'captcha-id',
          backgroundImage: btoa('bg'),
          sliderImage: btoa('slider'),
          y: 80,
        })
      )

      await userEvent.fill(usernameInput, 'echo')
      await userEvent.fill(passwordInput, 'any-password')

      await userEvent.click(signInButton)

      // Wait for login call and then captcha challenge call
      await vi.waitFor(() => {
        expect(mockFetch).toHaveBeenCalledTimes(2)
        expect(mockFetch).toHaveBeenCalledWith('/api/auth/captcha/challenge')
      })
    })
  })

  it('navigates to redirectTo when provided', async () => {
    mockFetch.mockResolvedValue(
      jsonResponse({ accessToken: 'gateway-token', username: 'echo' })
    )

    const screen = await render(<UserAuthForm redirectTo='/settings' />)

    await userEvent.fill(screen.getByPlaceholder('auth.username'), 'echo')
    await userEvent.fill(screen.getByPlaceholder('auth.password'), 'any-password')

    await userEvent.click(screen.getByRole('button', { name: 'auth.signIn' }))

    await vi.waitFor(() => expect(mockFetch).toHaveBeenCalledOnce())

    await vi.waitFor(() =>
      expect(navigate).toHaveBeenCalledWith({
        to: '/settings',
        replace: true,
      })
    )
  })

  it('does not navigate when login fails', async () => {
    mockFetch.mockResolvedValue(
      jsonResponse({ error: 'Invalid username or password' }, 401)
    )

    const screen = await render(<UserAuthForm />)

    await userEvent.fill(screen.getByPlaceholder('auth.username'), 'echo')
    await userEvent.fill(screen.getByPlaceholder('auth.password'), 'wrong')
    await userEvent.click(screen.getByRole('button', { name: 'auth.signIn' }))

    await vi.waitFor(() => expect(mockFetch).toHaveBeenCalledOnce())
    expect(setUserMock).not.toHaveBeenCalled()
    expect(setAccessTokenMock).not.toHaveBeenCalled()
    expect(navigate).not.toHaveBeenCalled()
  })
})
