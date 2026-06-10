import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'

export function useAdminAuditStats(period: string = '7') {
  return useQuery({
    queryKey: ['admin-audit-stats', period],
    queryFn: () => getApi().getAdminAuditStats(period),
    staleTime: 5 * 60_000,
  })
}
