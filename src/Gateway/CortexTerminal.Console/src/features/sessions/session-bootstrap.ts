import type { CreateSessionResponse } from '@/services/console-api'

const pendingSessionCreations = new Map<
  string,
  Promise<CreateSessionResponse>
>()

export function getOrStartSessionCreation(
  bootstrapId: string,
  createSession: () => Promise<CreateSessionResponse>
) {
  const existing = pendingSessionCreations.get(bootstrapId)
  if (existing) {
    return existing
  }

  const pending = createSession().finally(() => {
    pendingSessionCreations.delete(bootstrapId)
  })

  pendingSessionCreations.set(bootstrapId, pending)
  return pending
}

export function clearPendingSessionCreations() {
  pendingSessionCreations.clear()
}
