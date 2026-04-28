import { createFileRoute } from '@tanstack/react-router'
import { WorkerDetailPage } from '@/features/workers/worker-detail-page'

export const Route = createFileRoute('/_authenticated/workers/$workerId')({
  component: WorkerDetailPage,
})
