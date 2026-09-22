import { createFileRoute, redirect } from '@tanstack/react-router'
import { useAuthStore } from '@/stores/auth-store'
import { ActivatePage } from '@/features/activate/activate-page'

export const Route = createFileRoute('/(auth)/activate')({
  validateSearch: (search: Record<string, unknown>) => ({
    code: (search.code as string) ?? '',
  }),
  beforeLoad: () => {
    const accessToken = useAuthStore.getState().auth.accessToken
    if (!accessToken) {
      throw redirect({ to: '/sign-in', search: { redirect: '/activate' } })
    }
  },
  component: ActivatePage,
})
