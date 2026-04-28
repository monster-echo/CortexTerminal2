import { createFileRoute } from '@tanstack/react-router'
import { SessionListPage } from '@/features/sessions/session-list-page'

export const Route = createFileRoute('/_authenticated/sessions/')({
  component: SessionListPage,
})
