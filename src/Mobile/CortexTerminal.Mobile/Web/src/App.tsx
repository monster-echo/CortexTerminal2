import { useMemo, useState, useEffect } from "react"
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

export function App() {
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
              <IonLabel color="medium">Loading...</IonLabel>
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
              <IonLabel>Home</IonLabel>
            </IonTabButton>
            <IonTabButton tab="sessions" href="/sessions">
              <IonIcon icon={terminalOutline} />
              <IonLabel>Sessions</IonLabel>
            </IonTabButton>
            <IonTabButton tab="workers" href="/workers">
              <IonIcon icon={serverOutline} />
              <IonLabel>Workers</IonLabel>
            </IonTabButton>
            <IonTabButton tab="settings" href="/settings">
              <IonIcon icon={settingsOutline} />
              <IonLabel>Settings</IonLabel>
            </IonTabButton>
          </IonTabBar>
        </IonTabs>
      </IonReactRouter>
    </IonApp>
  )
}
