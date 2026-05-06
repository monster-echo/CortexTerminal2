import { useMemo, useState, useEffect } from "react"
import { useTranslation } from "react-i18next"
import { Redirect, Route, Switch } from "react-router-dom"
import {
  IonApp,
  IonIcon,
  IonLabel,
  IonPage,
  IonContent,
  IonRouterOutlet,
  IonTabBar,
  IonTabButton,
  IonTabs,
  setupIonicReact,
} from "@ionic/react"
import { IonReactRouter } from "@ionic/react-router"
import {
  homeOutline,
  terminalOutline,
  settingsOutline,
  serverOutline,
} from "ionicons/icons"
import { createNativeBridge } from "./bridge/nativeBridge"
import { createConsoleApi } from "./services/consoleApi"
import { createAuthService } from "./services/auth"
import { LoginPage } from "./pages/LoginPage"
import { DashboardPage } from "./pages/DashboardPage"
import { SessionListPage } from "./pages/SessionListPage"
import { WorkerListPage } from "./pages/WorkerListPage"
import { WorkerDetailPage } from "./pages/WorkerDetailPage"
import { SettingsPage } from "./pages/SettingsPage"
import { SessionDetailPage } from "./pages/SessionDetailPage"

setupIonicReact({ mode: "ios" })

// Apply stored theme on startup
type Theme = "light" | "dark" | "system"
function applyTheme(theme: Theme) {
  const root = document.documentElement
  if (theme === "system") {
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    root.classList.toggle("dark", prefersDark)
  } else {
    root.classList.toggle("dark", theme === "dark")
  }
}
const storedTheme = (localStorage.getItem("theme") as Theme) ?? "system"
applyTheme(storedTheme)

// Listen for system theme changes when in "system" mode
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
  const current = (localStorage.getItem("theme") as Theme) ?? "system"
  if (current === "system") applyTheme("system")
})

export function App() {
  const { t } = useTranslation()
  const bridge = useMemo(() => createNativeBridge(), [])
  const api = useMemo(() => createConsoleApi(bridge), [bridge])
  const auth = useMemo(() => createAuthService(bridge), [bridge])
  const [isAuthenticated, setAuthenticated] = useState(false)
  const [username, setUsername] = useState<string | null>(null)
  const [isChecking, setIsChecking] = useState(true)

  useEffect(() => {
    auth
      .isAuthenticated()
      .then((authed) => {
        if (authed) {
          return auth.getSession().then((session) => {
            setUsername(session?.username ?? null)
            setAuthenticated(true)
          })
        }
      })
      .catch(() => {})
      .finally(() => setIsChecking(false))
  }, [auth])

  const handleLogin = async () => {
    const session = await auth.getSession()
    setUsername(session?.username ?? null)
    setAuthenticated(true)
  }

  const handleLogout = async () => {
    await auth.logout()
    setUsername(null)
    setAuthenticated(false)
  }

  // Listen for OAuth callback events from native
  useEffect(() => {
    const unsubSuccess = bridge.onEvent(
      "auth",
      "oauth.success",
      (payload: unknown) => {
        const { username } = payload as { username?: string }
        setUsername(username ?? null)
        setAuthenticated(true)
      },
    )
    const unsubError = bridge.onEvent(
      "auth",
      "oauth.error",
      (payload: unknown) => {
        const { error } = payload as { error?: string }
        console.error("OAuth error:", error)
      },
    )
    return () => {
      unsubSuccess()
      unsubError()
    }
  }, [bridge])

  if (isChecking) {
    return (
      <IonApp>
        <IonPage>
          <IonContent>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                height: "100%",
              }}
            >
              <IonLabel color="medium">{t('common.loading')}</IonLabel>
            </div>
          </IonContent>
        </IonPage>
      </IonApp>
    )
  }

  if (!isAuthenticated) {
    return (
      <IonApp>
        <IonReactRouter>
          <IonRouterOutlet>
            <Switch>
              <Route
                exact
                path="/login"
                render={() => (
                  <LoginPage bridge={bridge} onLogin={handleLogin} />
                )}
              />
              <Redirect to="/login" />
            </Switch>
          </IonRouterOutlet>
        </IonReactRouter>
      </IonApp>
    )
  }

  return (
    <IonApp>
      <IonReactRouter>
        <IonTabs>
          <IonRouterOutlet>
            <Switch>
              <Route
                exact
                path="/dashboard"
                render={() => <DashboardPage api={api} />}
              />
              <Route
                exact
                path="/sessions"
                render={() => <SessionListPage api={api} />}
              />
              <Route
                path="/sessions/:sessionId"
                render={({ match }) => (
                  <SessionDetailPage
                    bridge={bridge}
                    sessionId={match.params.sessionId}
                  />
                )}
              />
              <Route
                exact
                path="/workers"
                render={() => <WorkerListPage api={api} />}
              />
              <Route
                path="/workers/:workerId"
                render={({ match }) => (
                  <WorkerDetailPage
                    api={api}
                    workerId={match.params.workerId}
                  />
                )}
              />
              <Route
                exact
                path="/settings"
                render={() => (
                  <SettingsPage
                    username={username}
                    onLogout={handleLogout}
                    api={api}
                  />
                )}
              />
              <Redirect to="/dashboard" />
            </Switch>
          </IonRouterOutlet>
          <IonTabBar slot="bottom">
            <IonTabButton tab="dashboard" href="/dashboard">
              <IonIcon icon={homeOutline} />
              <IonLabel>{t('nav.home')}</IonLabel>
            </IonTabButton>
            <IonTabButton tab="sessions" href="/sessions">
              <IonIcon icon={terminalOutline} />
              <IonLabel>{t('nav.sessions')}</IonLabel>
            </IonTabButton>
            <IonTabButton tab="workers" href="/workers">
              <IonIcon icon={serverOutline} />
              <IonLabel>{t('nav.workers')}</IonLabel>
            </IonTabButton>
            <IonTabButton tab="settings" href="/settings">
              <IonIcon icon={settingsOutline} />
              <IonLabel>{t('nav.settings')}</IonLabel>
            </IonTabButton>
          </IonTabBar>
        </IonTabs>
      </IonReactRouter>
    </IonApp>
  )
}
