import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'

const STORAGE_KEY = 'cortex_terminal_artifact_unread'

interface ArtifactUnreadState {
  lastSeenAt: Record<string, string>
  markSeen: (sessionId: string, latestUploadedAt: string) => void
}

export const useArtifactUnreadStore = create<ArtifactUnreadState>()(
  persist(
    (set) => ({
      lastSeenAt: {},
      markSeen: (sessionId, latestUploadedAt) =>
        set((state) => {
          const current = state.lastSeenAt[sessionId]
          if (current && new Date(current) >= new Date(latestUploadedAt)) return state
          return { lastSeenAt: { ...state.lastSeenAt, [sessionId]: latestUploadedAt } }
        }),
    }),
    {
      name: STORAGE_KEY,
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ lastSeenAt: state.lastSeenAt }),
      version: 1,
    }
  )
)
