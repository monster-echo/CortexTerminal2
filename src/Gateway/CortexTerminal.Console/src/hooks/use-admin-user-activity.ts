import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'

export function useAdminUserActivity() {
  return useQuery({
    queryKey: ['admin-user-activity'],
    queryFn: () => getApi().getAdminUserActivity(),
    staleTime: 10_000,
    refetchInterval: 10_000,
  })
}
