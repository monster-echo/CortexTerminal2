import { createFileRoute, redirect } from '@tanstack/react-router'
import { useAuthStore } from '@/stores/auth-store'
import { ActivatePage } from '@/features/activate/activate-page'

export const Route = createFileRoute('/(auth)/activate')({
  beforeLoad: () => {
    const accessToken = useAuthStore.getState().auth.accessToken
    if (!accessToken) {
      throw redirect({ to: '/sign-in', search: { redirect: '/activate' } })
    }
  },
  component: ActivatePage,
})
