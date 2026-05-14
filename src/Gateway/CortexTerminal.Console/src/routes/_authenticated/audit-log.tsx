import { createFileRoute, redirect } from '@tanstack/react-router'
import { AuditLogPage } from '@/features/audit-log'
import { useAuthStore } from '@/stores/auth-store'

export const Route = createFileRoute('/_authenticated/audit-log')({
  beforeLoad: () => {
    const user = useAuthStore.getState().auth.user
    if (user?.role !== 'admin') {
      throw redirect({ to: '/dashboard' })
    }
  },
  component: AuditLogPage,
})
