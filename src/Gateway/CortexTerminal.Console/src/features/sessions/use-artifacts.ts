import { useEffect, useMemo, useRef } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useTranslation } from 'react-i18next'
import type { ArtifactChangedEvent } from '@/services/console-api'
import { createArtifactGateway } from './artifacts-gateway'
import { useAuthStore } from '@/stores/auth-store'
import { getApi } from '@/lib/api'

export interface ArtifactUploadOptions {
  filename: string
  sizeBytes: number
}

export function useArtifacts(sessionId: string) {
  const queryClient = useQueryClient()
  const { t } = useTranslation()
  const queryKey = useMemo(() => ['artifacts', sessionId] as const, [sessionId])

  const query = useQuery({
    queryKey,
    queryFn: () => getApi().listArtifacts(sessionId),
  })

  const gatewayRef = useRef<ReturnType<typeof createArtifactGateway> | null>(null)

  useEffect(() => {
    const gateway = createArtifactGateway({
      accessTokenFactory: () => useAuthStore.getState().auth.accessToken,
    })
    gatewayRef.current = gateway

    const applyEvent = (evt: ArtifactChangedEvent) => {
      if (evt.sessionId !== sessionId) return
      const incoming = evt.artifact
      queryClient.setQueryData<NonNullable<ArtifactChangedEvent['artifact']>[]>(queryKey, (old = []) => {
        if (evt.changeType === 'deleted') {
          return old.filter((a) => a.id !== evt.artifactId)
        }
        if (!incoming) return old
        if (evt.changeType === 'created') {
          if (old.some((a) => a.id === incoming.id)) return old
          return [...old, incoming].sort(
            (a, b) => new Date(a.uploadedAt).getTime() - new Date(b.uploadedAt).getTime()
          )
        }
        return old.map((a) => (a.id === incoming.id ? incoming : a))
      })

      if (evt.changeType === 'created' && incoming && incoming.origin === 'worker') {
        toast.success(t('terminal.artifacts.workerUploaded', { filename: incoming.filename }))
      }
    }

    gateway
      .start({ onArtifactChanged: applyEvent })
      .catch((err) => console.error('Failed to start artifact gateway', err))

    return () => {
      gateway.stop().catch(() => undefined)
      gatewayRef.current = null
    }
  }, [sessionId, queryKey, queryClient])

  return {
    artifacts: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
