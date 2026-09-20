import { createFileRoute, redirect } from '@tanstack/react-router'
import { RedeemCodesPage } from '@/features/billing/redeem-codes'
import { useAuthStore } from '@/stores/auth-store'

export const Route = createFileRoute('/_authenticated/billing/redeem-codes')({
  beforeLoad: () => {
    const user = useAuthStore.getState().auth.user
    if (user?.role !== 'admin') {
      throw redirect({ to: '/dashboard' })
    }
  },
  component: RedeemCodesPage,
})
