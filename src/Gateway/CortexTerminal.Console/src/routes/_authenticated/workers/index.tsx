import { createFileRoute } from '@tanstack/react-router'
import { WorkerListPage } from '@/features/workers'

export const Route = createFileRoute('/_authenticated/workers/')({
  component: WorkerListPage,
})
