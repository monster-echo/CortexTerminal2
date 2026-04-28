import { useCallback, useEffect, useMemo, useState } from "react"
import { AppLayout } from "./components/AppLayout"
import { resolveConsoleRoute, toConsoleHash } from "./console/consoleApp"
import { DashboardPage } from "./pages/DashboardPage"
import { LoginPage } from "./pages/LoginPage"
import { RegisterPage } from "./pages/RegisterPage"
import { SessionDetailPage } from "./pages/SessionDetailPage"
import { SessionListPage } from "./pages/SessionListPage"
import { SettingsPage } from "./pages/SettingsPage"
import { WorkerDetailPage } from "./pages/WorkerDetailPage"
import { WorkerListPage } from "./pages/WorkerListPage"
import { createAuthService, type AuthSession } from "./services/auth"
import { createConsoleApi } from "./services/consoleApi"
import { createTerminalGateway } from "./services/terminalGateway"

export function App() {
  const auth = useMemo(() => createAuthService(window.localStorage), [])
  const [session, setSession] = useState<AuthSession | null>(() => auth.getSession())
  const [hash, setHash] = useState(() => window.location.hash)

  const navigate = useCallback((path: string) => {
    const nextHash = toConsoleHash(path)
    if (window.location.hash !== nextHash) {
      window.location.hash = nextHash
      return
    }
    setHash(nextHash)
  }, [])

  const handleUnauthorized = useCallback(() => {
    auth.clearSession()
    setSession(null)
    const loginHash = toConsoleHash("/login")
    window.location.hash = loginHash
    setHash(loginHash)
  }, [auth])

  const api = useMemo(
    () =>
      createConsoleApi({
        fetchFn: window.fetch.bind(window),
        getToken: () => auth.getToken(),
        onUnauthorized: handleUnauthorized,
      }),
    [auth, handleUnauthorized]
  )
  const terminalGateway = useMemo(
    () =>
      createTerminalGateway({
        accessTokenFactory: () => auth.getToken(),
      }),
    [auth]
  )

  useEffect(() => {
    const onHashChange = () => {
      setHash(window.location.hash)
    }
    window.addEventListener("hashchange", onHashChange)
    return () => {
      window.removeEventListener("hashchange", onHashChange)
    }
  }, [])

  const route = resolveConsoleRoute(hash, auth.isAuthenticated())

  const handleLogin = async (username: string) => {
    const nextSession = auth.setSession(await api.login(username))
    setSession(nextSession)
  }

  const handleLogout = () => {
    auth.clearSession()
    setSession(null)
    navigate("/login")
  }

  const renderPage = () => {
    switch (route.kind) {
      case "login":
        return <LoginPage login={handleLogin} navigate={navigate} />
      case "register":
        return <RegisterPage navigate={navigate} />
      case "dashboard":
        return <DashboardPage api={api} navigate={navigate} />
      case "session-list":
        return <SessionListPage api={api} navigate={navigate} />
      case "session-detail":
        return (
          <SessionDetailPage
            api={api}
            navigate={navigate}
            sessionId={route.sessionId}
            terminalGateway={terminalGateway}
          />
        )
      case "worker-list":
        return <WorkerListPage api={api} navigate={navigate} />
      case "worker-detail":
        return <WorkerDetailPage api={api} navigate={navigate} workerId={route.workerId} />
      case "settings":
        return <SettingsPage username={session?.username ?? null} onLogout={handleLogout} />
      default:
        return null
    }
  }

  return (
    <AppLayout
      currentPath={route.path}
      isAuthenticated={session !== null}
      onLogout={handleLogout}
      onNavigate={navigate}
      username={session?.username ?? null}
    >
      {renderPage()}
    </AppLayout>
  )
}
