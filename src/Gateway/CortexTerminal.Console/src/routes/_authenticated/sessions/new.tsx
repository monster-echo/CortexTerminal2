import { createFileRoute } from '@tanstack/react-router'
import { NewSessionPage } from '@/features/sessions/new-session-page'

export const Route = createFileRoute('/_authenticated/sessions/new')({
  validateSearch: (search: Record<string, unknown>) => ({
    bootstrapId:
      typeof search.bootstrapId === 'string' ? search.bootstrapId : undefined,
  }),
  component: RouteComponent,
})

function RouteComponent() {
  const { bootstrapId } = Route.useSearch()
  return <NewSessionPage bootstrapId={bootstrapId} />
}
