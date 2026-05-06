import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from '@tanstack/react-router'
import { createTerminalGateway } from '@/services/terminal-gateway'
import { ConsoleApiError } from '@/services/console-api'
import { TerminalView } from '@/terminal/terminal-view'
import { Button } from '@/components/ui/button'
import { Loader2 } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { getApi } from '@/lib/api'

export function SessionDetailPage(props: { sessionId: string }) {
  const { sessionId } = props
  const navigate = useNavigate()

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
    retry: (failureCount, error) => {
      if (error instanceof ConsoleApiError && error.status === 404) {
        return false
      }
      return failureCount < 2
    },
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

  const isNotFound =
    sessionQuery.error instanceof ConsoleApiError &&
    sessionQuery.error.status === 404

  if (isNotFound) {
    return (
      <div className='h-svh'>
        <div className='m-auto flex h-full w-full flex-col items-center justify-center gap-2'>
          <h1 className='text-[7rem] leading-tight font-bold'>404</h1>
          <span className='font-medium'>Session Not Found</span>
          <p className='text-center text-muted-foreground'>
            This session no longer exists (the server may have restarted).
          </p>
          <div className='mt-6 flex gap-4'>
            <Button
              onClick={() =>
                navigate({ to: '/sessions' })
              }
            >
              Go to Sessions
            </Button>
          </div>
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
