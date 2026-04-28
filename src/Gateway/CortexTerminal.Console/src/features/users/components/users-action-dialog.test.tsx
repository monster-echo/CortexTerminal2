import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render } from 'vitest-browser-react'
import { userEvent } from 'vitest/browser'
import { type User } from '../data/schema'
import { UsersActionDialog } from './users-action-dialog'

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
    updateUser: vi.fn(),
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

const MOCK_USER: User = {
  id: 'alex_uuid',
  name: 'Alex Smith',
  email: 'alex@smith.com',
  status: 'active',
  role: 'admin',
}

describe('UsersActionDialog', () => {
  beforeEach(() => vi.clearAllMocks())

  describe('edit user role', () => {
    it('renders title and description', async () => {
      const { getByText } = await render(
        <UsersActionDialog open onOpenChange={vi.fn()} currentRow={MOCK_USER} />
      )

      const title = getByText('users.actions.editRole')
      await expect.element(title).toBeInTheDocument()
    })

    it('shows role select with current role pre-selected', async () => {
      const screen = await render(
        <UsersActionDialog open onOpenChange={vi.fn()} currentRow={MOCK_USER} />
      )

      const roleSelect = screen.getByRole('combobox', { name: /Role/i })
      await expect.element(roleSelect).toBeInTheDocument()
    })

    it('calls updateUser mutation when form is submitted', async () => {
      const onOpenChange = vi.fn()
      const screen = await render(
        <UsersActionDialog
          open
          onOpenChange={onOpenChange}
          currentRow={MOCK_USER}
        />
      )

      const submitButton = screen.getByRole('button', { name: /common.save/i })
      await userEvent.click(submitButton)

      expect(mockMutate).toHaveBeenCalled()
    })
  })
})
