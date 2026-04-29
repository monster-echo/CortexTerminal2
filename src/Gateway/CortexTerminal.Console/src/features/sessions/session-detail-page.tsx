import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { createTerminalGateway } from '@/services/terminal-gateway'
import { TerminalView } from '@/terminal/terminal-view'
import { Loader2 } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { getApi } from '@/lib/api'

export function SessionDetailPage(props: { sessionId: string }) {
  const { sessionId } = props

  const api = getApi()

  const gateway = useMemo(
    () =>
      createTerminalGateway({
        accessTokenFactory: () => useAuthStore.getState().auth.accessToken,
      }),
    []
  )

  const sessionQuery = useQuery({
    queryKey: ['sessions', sessionId],
    queryFn: () => api.getSession(sessionId),
  })

  const session = sessionQuery.data

  if (sessionQuery.isLoading) {
    return (
      <div className='flex h-full flex-1 items-center justify-center'>
        <div className='flex items-center gap-2 text-sm text-muted-foreground'>
          <Loader2 className='size-4 animate-spin' /> Loading session...
        </div>
      </div>
    )
  }

  if (sessionQuery.isError || !session) {
    return (
      <div className='flex h-full flex-1 items-center justify-center'>
        <p className='text-sm text-destructive'>
          {sessionQuery.error instanceof Error
            ? sessionQuery.error.message
            : 'Unknown error'}
        </p>
      </div>
    )
  }

  return (
    <div className='flex h-full flex-col'>
      <TerminalView
        gateway={gateway}
        sessionId={session.sessionId}
        workerId={session.workerId}
        sessionStatus={session.status}
      />
    </div>
  )
}
