import { createFileRoute, redirect } from '@tanstack/react-router'
import { MembershipManagementPage } from '@/features/billing/membership'
import { useAuthStore } from '@/stores/auth-store'

export const Route = createFileRoute('/_authenticated/billing/membership')({
  beforeLoad: () => {
    const user = useAuthStore.getState().auth.user
    if (user?.role !== 'admin') {
      throw redirect({ to: '/dashboard' })
    }
  },
  component: MembershipManagementPage,
})
