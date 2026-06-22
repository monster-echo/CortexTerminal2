import { useAuthStore } from '@/stores/auth-store'
import { AdminDashboard } from './admin-dashboard'
import { UserDashboard } from './user-dashboard'

export function Dashboard() {
  const user = useAuthStore((state) => state.auth.user)
  if (user?.role === 'admin') return <AdminDashboard />
  return <UserDashboard />
}
