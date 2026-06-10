import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'

export function useAdminStats() {
  return useQuery({
    queryKey: ['admin-stats'],
    queryFn: () => getApi().getAdminStats(),
    staleTime: 10_000,
    refetchInterval: 10_000,
  })
}
