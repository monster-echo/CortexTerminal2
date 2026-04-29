import { useQuery } from '@tanstack/react-query'
import { getApi } from '@/lib/api'

export function useWorkers() {
  return useQuery({
    queryKey: ['workers'],
    queryFn: () => getApi().listWorkers(),
    staleTime: 30_000,
  })
}
