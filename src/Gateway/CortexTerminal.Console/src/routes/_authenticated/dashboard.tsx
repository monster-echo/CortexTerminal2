import { createFileRoute } from '@tanstack/react-router'
import { Dashboard as DashboardPage } from '@/features/dashboard'

export const Route = createFileRoute('/_authenticated/dashboard')({
  component: DashboardPage,
})
