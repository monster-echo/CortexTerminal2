import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'

export const CURRENT_USER_QUERY_KEY = ['me', 'profile'] as const

export function useCurrentUser() {
  return useQuery({
    queryKey: CURRENT_USER_QUERY_KEY,
    queryFn: () => getApi().getMyProfile(),
    staleTime: 5 * 60 * 1000,
  })
}
