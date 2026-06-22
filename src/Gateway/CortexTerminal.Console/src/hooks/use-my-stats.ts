import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'

export function useMyStats() {
  return useQuery({
    queryKey: ['my-stats'],
    queryFn: () => getApi().getMyStats(),
    staleTime: 10_000,
    refetchInterval: 10_000,
  })
}
