import { useState } from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from 'vitest-browser-react'
import { userEvent } from 'vitest/browser'
import { type User } from '../data/schema'
import { UsersDeleteDialog } from './users-delete-dialog'

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
    deleteUser: vi.fn(),
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

const MOCK_USER: User = {
  id: 'user-delete-test',
  name: 'John Doe',
  email: 'johndoe@example.com',
  status: 'active',
  role: 'user',
}

describe('UsersDeleteDialog', () => {
  beforeEach(() => vi.clearAllMocks())

  it('renders the dialog with the correct title, description, input and buttons', async () => {
    const { getByRole } = await render(
      <UsersDeleteDialog open onOpenChange={vi.fn()} currentRow={MOCK_USER} />
    )

    const title = getByRole('heading', {
      level: 2,
      name: /Delete User/i,
    })
    const nameInput = getByRole('textbox')
    const cancelButton = getByRole('button', { name: /Cancel/i })
    const deleteButton = getByRole('button', { name: /common.delete/i })

    await expect.element(title).toBeInTheDocument()
    await expect.element(nameInput).toBeInTheDocument()
    await expect.element(cancelButton).toBeInTheDocument()
    await expect.element(deleteButton).toBeInTheDocument()
    await expect.element(deleteButton).toBeDisabled()
  })

  it('keeps the delete button disabled until the name input is filled correctly', async () => {
    const { getByRole } = await render(
      <UsersDeleteDialog open onOpenChange={vi.fn()} currentRow={MOCK_USER} />
    )

    const nameInput = getByRole('textbox')
    const deleteButton = getByRole('button', { name: /common.delete/i })

    await expect.element(deleteButton).toBeDisabled()

    await userEvent.fill(nameInput, 'wrong-name')
    await expect.element(deleteButton).toBeDisabled()

    await userEvent.fill(nameInput, MOCK_USER.name)
    await expect.element(deleteButton).toBeEnabled()
  })

  it('closes the dialog when the cancel button is clicked', async () => {
    const onOpenChange = vi.fn()
    const { getByRole } = await render(
      <UsersDeleteDialog
        open
        onOpenChange={onOpenChange}
        currentRow={MOCK_USER}
      />
    )

    const cancelButton = getByRole('button', { name: /Cancel/i })
    await userEvent.click(cancelButton)

    expect(onOpenChange).toHaveBeenCalledOnce()
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('resets the name input when the dialog is closed and reopened', async () => {
    function Harness() {
      const [open, setOpen] = useState(true)
      return (
        <>
          <button type='button' onClick={() => setOpen(true)}>
            Reopen
          </button>
          {open ? (
            <UsersDeleteDialog
              open={open}
              onOpenChange={setOpen}
              currentRow={MOCK_USER}
            />
          ) : null}
        </>
      )
    }

    const { getByRole } = await render(<Harness />)

    const nameInput = getByRole('textbox')
    await userEvent.fill(nameInput, MOCK_USER.name)
    await expect.element(nameInput).toHaveValue(MOCK_USER.name)

    const closeButton = getByRole('button', { name: /Cancel/i })
    await userEvent.click(closeButton)

    const reopenButton = getByRole('button', { name: /Reopen/i })
    await userEvent.click(reopenButton)
    await expect.element(nameInput).toHaveValue('')
  })

  it('calls deleteUser mutation when deleted successfully', async () => {
    const onOpenChange = vi.fn()
    const { getByRole } = await render(
      <UsersDeleteDialog
        open
        onOpenChange={onOpenChange}
        currentRow={MOCK_USER}
      />
    )

    const nameInput = getByRole('textbox')
    const deleteButton = getByRole('button', { name: /common.delete/i })

    await expect.element(deleteButton).toBeDisabled()

    await userEvent.fill(nameInput, MOCK_USER.name)

    await expect.element(deleteButton).toBeEnabled()

    await userEvent.click(deleteButton)

    expect(mockMutate).toHaveBeenCalledOnce()
  })

  it('deletes successfully when press Enter key on the name input', async () => {
    const { getByRole } = await render(
      <UsersDeleteDialog open onOpenChange={vi.fn()} currentRow={MOCK_USER} />
    )

    const nameInput = getByRole('textbox')
    const deleteButton = getByRole('button', { name: /common.delete/i })

    await expect.element(deleteButton).toBeDisabled()

    await userEvent.fill(nameInput, MOCK_USER.name)
    await expect.element(deleteButton).toBeEnabled()

    await userEvent.keyboard('{Enter}')

    expect(mockMutate).toHaveBeenCalledOnce()
  })
})
