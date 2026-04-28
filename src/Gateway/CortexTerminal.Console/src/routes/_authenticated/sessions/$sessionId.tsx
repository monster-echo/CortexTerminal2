import { createFileRoute } from '@tanstack/react-router'
import { SessionDetailPage } from '@/features/sessions/session-detail-page'

export const Route = createFileRoute('/_authenticated/sessions/$sessionId')({
  component: RouteComponent,
})

function RouteComponent() {
  const { sessionId } = Route.useParams()
  return <SessionDetailPage sessionId={sessionId} />
}
