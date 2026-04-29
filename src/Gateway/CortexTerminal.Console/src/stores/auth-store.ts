import { create } from 'zustand'
import { getCookie, setCookie, removeCookie } from '@/lib/cookies'

const ACCESS_TOKEN = 'cortex_terminal_access_token'
const REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000 // 24 hours

interface AuthUser {
  username: string
}

interface AuthState {
  auth: {
    user: AuthUser | null
    setUser: (user: AuthUser | null) => void
    accessToken: string
    setAccessToken: (accessToken: string) => void
    resetAccessToken: () => void
    reset: () => void
  }
}

let refreshTimer: ReturnType<typeof setInterval> | null = null

async function refreshToken() {
  const token = useAuthStore.getState().auth.accessToken
  if (!token) return

  try {
    const response = await fetch('/api/auth/refresh', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    })
    if (!response.ok) return
    const data = (await response.json()) as { accessToken: string }
    useAuthStore.getState().auth.setAccessToken(data.accessToken)
  } catch {
    // Silently ignore refresh failures — the 401 retry in console-api will handle it
  }
}

function startRefreshTimer() {
  stopRefreshTimer()
  refreshTimer = setInterval(refreshToken, REFRESH_INTERVAL_MS)
}

function stopRefreshTimer() {
  if (refreshTimer) {
    clearInterval(refreshTimer)
    refreshTimer = null
  }
}

export const useAuthStore = create<AuthState>()((set) => {
  const cookieState = getCookie(ACCESS_TOKEN)
  const initToken = cookieState ? JSON.parse(cookieState) : ''
  const initUser = getUserFromToken(initToken)

  if (initToken) {
    startRefreshTimer()
  }

  return {
    auth: {
      user: initUser,
      setUser: (user) =>
        set((state) => ({ ...state, auth: { ...state.auth, user } })),
      accessToken: initToken,
      setAccessToken: (accessToken) =>
        set((state) => {
          setCookie(ACCESS_TOKEN, JSON.stringify(accessToken))
          startRefreshTimer()
          return {
            ...state,
            auth: {
              ...state.auth,
              accessToken,
              user: state.auth.user ?? getUserFromToken(accessToken),
            },
          }
        }),
      resetAccessToken: () =>
        set((state) => {
          removeCookie(ACCESS_TOKEN)
          stopRefreshTimer()
          return {
            ...state,
            auth: { ...state.auth, accessToken: '', user: null },
          }
        }),
      reset: () =>
        set((state) => {
          removeCookie(ACCESS_TOKEN)
          stopRefreshTimer()
          return {
            ...state,
            auth: { ...state.auth, user: null, accessToken: '' },
          }
        }),
    },
  }

  function getUserFromToken(accessToken: string): AuthUser | null {
    if (!accessToken) {
      return null
    }

    try {
      const payload = accessToken.split('.')[1]
      if (!payload) {
        return null
      }

      const normalized = payload.replace(/-/g, '+').replace(/_/g, '/')
      const decoded = JSON.parse(atob(normalized)) as {
        sub?: string
        unique_name?: string
        name?: string
      }

      const username = decoded.sub ?? decoded.unique_name ?? decoded.name
      return username ? { username } : null
    } catch {
      return null
    }
  }
})
