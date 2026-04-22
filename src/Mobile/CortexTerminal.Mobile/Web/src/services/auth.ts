export interface AuthSession {
  token: string
  username: string
}

export interface AuthService {
  getSession(): AuthSession | null
  getToken(): string | null
  isAuthenticated(): boolean
  setSession(session: AuthSession): AuthSession
  clearSession(): void
}

const defaultStorageKey = "gateway-console-auth"

export function createAuthService(
  storage: Pick<Storage, "getItem" | "setItem" | "removeItem">,
  storageKey = defaultStorageKey
): AuthService {
  const getSession = () => {
    const raw = storage.getItem(storageKey)
    if (!raw) {
      return null
    }

    try {
      const parsed = JSON.parse(raw) as Partial<AuthSession>
      if (typeof parsed.token === "string" && typeof parsed.username === "string") {
        return {
          token: parsed.token,
          username: parsed.username,
        }
      }
    } catch {
      storage.removeItem(storageKey)
    }

    return null
  }

  return {
    getSession,
    getToken() {
      return getSession()?.token ?? null
    },
    isAuthenticated() {
      return getSession() !== null
    },
    setSession(session) {
      storage.setItem(storageKey, JSON.stringify(session))
      return session
    },
    clearSession() {
      storage.removeItem(storageKey)
    },
  }
}
