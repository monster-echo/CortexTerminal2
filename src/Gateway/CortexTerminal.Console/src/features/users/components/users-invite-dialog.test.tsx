import { useState } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from 'vitest-browser-react'
import { userEvent } from 'vitest/browser'
import { UsersInviteDialog } from './users-invite-dialog'

// Mock TanStack Query
const mockMutate = vi.fn()
vi.mock('@tanstack/react-query', () => ({
  useMutation: () => ({
    mutate: mockMutate,
    isPending: false,
  }),
  useQueryClient: () => ({
    invalidateQueries: vi.fn(),
  }),
}))

// Mock i18next
vi.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key: string) => key,
  }),
}))

// Mock console-api
vi.mock('@/services/console-api', () => ({
  createConsoleApi: () => ({
    inviteUser: vi.fn(),
  }),
}))

// Mock auth store
vi.mock('@/stores/auth-store', () => ({
  useAuthStore: {
    getState: () => ({
      auth: { accessToken: 'test-token', reset: vi.fn() },
    }),
  },
}))

// Mock toast
vi.mock('sonner', () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
  },
}))

describe('UsersInviteDialog', () => {
  beforeEach(() => vi.clearAllMocks())

  it('renders the dialog title and description', async () => {
    const { getByRole, getByText } = await render(
      <UsersInviteDialog open onOpenChange={vi.fn()} />
    )

    const title = getByRole('heading', {
      level: 2,
      name: /Invite User/i,
    })
    const desc = getByText(/Invite new user to join your team/i)

    await expect.element(title).toBeInTheDocument()
    await expect.element(desc).toBeInTheDocument()
  })

  it('closes when the dialog close button is clicked', async () => {
    const onOpenChange = vi.fn()
    const { getByRole } = await render(
      <UsersInviteDialog open onOpenChange={onOpenChange} />
    )

    const closeButton = getByRole('button', { name: /Close/i })
    await userEvent.click(closeButton)

    expect(onOpenChange).toHaveBeenCalledOnce()
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('closes when Cancel is clicked', async () => {
    const onOpenChange = vi.fn()
    const { getByRole } = await render(
      <UsersInviteDialog open onOpenChange={onOpenChange} />
    )

    const cancelButton = getByRole('button', { name: /common.cancel/i })
    await userEvent.click(cancelButton)

    expect(onOpenChange).toHaveBeenCalledOnce()
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('shows error messages when submitting empty form', async () => {
    const onOpenChange = vi.fn()
    const { getByRole, getByText } = await render(
      <UsersInviteDialog open onOpenChange={onOpenChange} />
    )

    const submitButton = getByRole('button', { name: /Invite/i })
    await userEvent.click(submitButton)

    await expect
      .element(getByText(/Please enter an email to invite./i))
      .toBeInTheDocument()
    await expect
      .element(getByText(/Role is required./i))
      .toBeInTheDocument()
  })

  it('resets entered values when the dialog is closed and reopened', async () => {
    function Harness() {
      const [open, setOpen] = useState(true)
      return (
        <>
          <button type='button' onClick={() => setOpen(true)}>
            Reopen
          </button>
          <UsersInviteDialog open={open} onOpenChange={setOpen} />
        </>
      )
    }

    const { getByRole } = await render(<Harness />)

    const EMAIL_VALUE = 'test@example.com'

    const emailInput = getByRole('textbox', { name: /Email/i })
    await userEvent.fill(emailInput, EMAIL_VALUE)

    await expect.element(emailInput).toHaveValue(EMAIL_VALUE)

    const cancelButton = getByRole('button', { name: /common.cancel/i })
    await userEvent.click(cancelButton)

    const reopenButton = getByRole('button', { name: /Reopen/i })
    await userEvent.click(reopenButton)

    await expect.element(emailInput).toHaveValue('')
  })

  it('calls inviteUser mutation when form is submitted successfully', async () => {
    const onOpenChange = vi.fn()
    const { getByRole } = await render(
      <UsersInviteDialog open onOpenChange={onOpenChange} />
    )

    const EMAIL_VALUE = 'test@example.com'

    const emailInput = getByRole('textbox', { name: /Email/i })
    await userEvent.fill(emailInput, EMAIL_VALUE)

    const roleSelect = getByRole('combobox', { name: /Role/i })
    await userEvent.click(roleSelect)
    await userEvent.click(getByRole('option', { name: /Admin/i }))

    const submitButton = getByRole('button', { name: /Invite/i })
    await userEvent.click(submitButton)

    expect(mockMutate).toHaveBeenCalledOnce()
    expect(mockMutate).toHaveBeenCalledWith({
      email: EMAIL_VALUE,
      role: 'admin',
    })
  })
})
