import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'

export function useSessions() {
  return useQuery({
    queryKey: ['sessions'],
    queryFn: () => getApi().listSessions(),
    staleTime: 15_000,
  })
}
