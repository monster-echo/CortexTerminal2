import { Redirect, Route } from "react-router-dom";
import { IonApp, IonSpinner, setupIonicReact } from "@ionic/react";
import { IonReactRouter } from "@ionic/react-router";
import { createHashHistory } from "history";
import { useEffect } from "react";
import AppLayout from "./components/AppLayout";
import { nativeBridge } from "./bridge/nativeBridge";
import { transport, registerSessionInvalidatedHandler } from "./bridge/runtime";
import SettingsFeaturePage from "./features/settings/SettingsFeaturePage";
import LoginPage from "./features/auth/LoginPage";
import SessionsPage from "./features/sessions/SessionsPage";
import TerminalSessionPage from "./features/sessions/TerminalSessionPage";
import WorkersPage from "./features/workers/WorkersPage";
import ActivatePage from "./features/activate/ActivatePage";
import {
  applyColorMode,
  getStoredMode,
  initColorMode,
  setStoredMode,
  type ColorMode,
} from "./theme/colorMode";
import { useAppStore, type AppStoreState } from "./store/appStore";
import { useAuthStore, type AuthState } from "./store/authStore";
import { authBridge } from "./bridge/modules/authBridge";
import { terminalBridge } from "./bridge/modules/terminalBridge";
import { useSessionStore, type SessionState } from "./store/sessionStore";
import "./theme/variables.css";

// Stable selector references for Zustand v5 + React 19 useSyncExternalStore.
// Inline arrow functions cause unstable getSnapshot references leading to
// "Maximum update depth exceeded" errors.
const selectColorMode = (s: AppStoreState) => s.colorMode;
const selectSetColorMode = (s: AppStoreState) => s.setColorMode;
const selectSetPlatformLabel = (s: AppStoreState) => s.setPlatformLabel;
const selectSetBridgeReady = (s: AppStoreState) => s.setBridgeReady;
const selectSetBridgeCapabilities = (s: AppStoreState) => s.setBridgeCapabilities;
const selectSetSystemInfo = (s: AppStoreState) => s.setSystemInfo;
const selectSetAppInfo = (s: AppStoreState) => s.setAppInfo;
const selectSetPendingNavigation = (s: AppStoreState) => s.setPendingNavigation;
const selectSetOffline = (s: AppStoreState) => s.setOffline;
const selectSetLastBridgeError = (s: AppStoreState) => s.setLastBridgeError;
const selectSetInitializing = (s: AppStoreState) => s.setInitializing;
const selectSetLanguage = (s: AppStoreState) => s.setLanguage;

const selectIsLoggedIn = (s: AuthState) => s.isLoggedIn;
const selectAuthLoading = (s: AuthState) => s.isLoading;
const selectSetSession = (s: AuthState) => s.setSession;
const selectClearSession = (s: AuthState) => s.clearSession;
const selectSetAuthLoading = (s: AuthState) => s.setLoading;

const selectSetWorkers = (s: SessionState) => s.setWorkers;
const selectSetSessions = (s: SessionState) => s.setSessions;
const selectSetGatewayLoaded = (s: SessionState) => s.setGatewayLoaded;
const selectIsInitializing = (s: AppStoreState) => s.isInitializing;

setupIonicReact({
  rippleEffect: true,
  swipeBackEnabled: true,
  hardwareBackButton: true,
  animated: true,
});

const history = createHashHistory();

export default function App({
  initialData,
}: {
  initialData?: { platform?: string };
}) {
  const setColorModeState = useAppStore(selectSetColorMode);
  const setPlatformLabel = useAppStore(selectSetPlatformLabel);
  const setBridgeReady = useAppStore(selectSetBridgeReady);
  const setBridgeCapabilities = useAppStore(selectSetBridgeCapabilities);
  const setSystemInfo = useAppStore(selectSetSystemInfo);
  const setAppInfo = useAppStore(selectSetAppInfo);
  const setPendingNavigation = useAppStore(selectSetPendingNavigation);
  const setOffline = useAppStore(selectSetOffline);
  const setLastBridgeError = useAppStore(selectSetLastBridgeError);
  const setInitializing = useAppStore(selectSetInitializing);
  const setLanguage = useAppStore(selectSetLanguage);
  const isInitializing = useAppStore(selectIsInitializing);
  const isLoggedIn = useAuthStore(selectIsLoggedIn);
  const authLoading = useAuthStore(selectAuthLoading);
  const setSession = useAuthStore(selectSetSession);
  const clearSession = useAuthStore(selectClearSession);
  const setAuthLoading = useAuthStore(selectSetAuthLoading);

  const setWorkers = useSessionStore(selectSetWorkers);
  const setSessions = useSessionStore(selectSetSessions);
  const setGatewayLoaded = useSessionStore(selectSetGatewayLoaded);

  useEffect(() => {
    if (initialData?.platform) {
      (window as any).platform = initialData.platform;
      setPlatformLabel(initialData.platform);
    }
  }, [initialData]);

  useEffect(() => {
    const checkSession = async () => {
      try {
        const session = await authBridge.getSession();
        if (session) {
          setSession({ username: session.username }, session.token);
        } else {
          clearSession();
        }
      } catch {
        clearSession();
      }
    };
    checkSession();
  }, [setSession, clearSession]);

  useEffect(() => {
    setColorModeState(getStoredMode() ?? initColorMode());

    (window as any).checkWebViewHealth = () => "HEALTHY";

    const bootstrap = async () => {
      try {
        const [capabilities, systemInfo, appInfo] = await Promise.all([
          nativeBridge.getCapabilities(),
          nativeBridge.getSystemInfo(),
          nativeBridge.getAppInfo(),
        ]);

        setBridgeCapabilities(capabilities);
        setSystemInfo(systemInfo);
        setAppInfo(appInfo);
        setBridgeReady(true);
        setLastBridgeError(null);

        // Sync theme & language from native preferences (authoritative source)
        try {
          const [savedColorMode, savedLanguage] = await Promise.all([
            nativeBridge.getStringValue("app.colorMode"),
            nativeBridge.getStringValue("app.language"),
          ]);

          if (savedColorMode && ["light", "dark", "system"].includes(savedColorMode)) {
            setStoredMode(savedColorMode as ColorMode);
            applyColorMode(savedColorMode as ColorMode);
            setColorModeState(savedColorMode as ColorMode);
          }

          if (savedLanguage && ["en", "zh"].includes(savedLanguage)) {
            setLanguage(savedLanguage as "en" | "zh");
          }
        } catch (e) {
          console.warn("[bootstrap] Failed to sync preferences from native:", e);
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.warn("Failed to bootstrap bridge state", error);
        setLastBridgeError(message);
      } finally {
        setInitializing(false);
      }
    };

    const onNativeMessage = (data: unknown) => {
      try {
        if (!data || typeof data !== "object") return;
        const typed = data as { type?: string; route?: string; payload?: string };

        if (typed.type === "auth.oauth.success") {
          const username = (data as any).username;
          if (username) setSession({ username }, "");
          return;
        }
        if (typed.type === "auth.oauth.error") {
          const error = (data as any).error;
          console.error("OAuth error:", error);
          return;
        }

        if (typed.type === "pushNavigate" && typed.route) {
          setPendingNavigation({
            hasPending: true,
            route: typed.route,
            payload: typeof typed.payload === "string" ? typed.payload : null,
          });
          history.push(typed.route);
        }
      } catch (error) {
        console.warn("Failed to handle native message", error);
      }
    };

    const loadPendingNavigation = async () => {
      try {
        const pending = await nativeBridge.getPendingNavigation();
        setPendingNavigation(pending);
        if (pending.hasPending && pending.route) {
          history.push(pending.route);
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.warn("Failed to load pending navigation", error);
        setLastBridgeError(message);
      }
    };

    const updateOnlineStatus = () => {
      setOffline(!navigator.onLine);
    };

    const unsubscribeNative = transport.onMessage(onNativeMessage);
    registerSessionInvalidatedHandler(() => clearSession());
    window.addEventListener("online", updateOnlineStatus);
    window.addEventListener("offline", updateOnlineStatus);
    bootstrap();
    loadPendingNavigation();
    updateOnlineStatus();

    return () => {
      delete (window as any).checkWebViewHealth;
      unsubscribeNative();
      window.removeEventListener("online", updateOnlineStatus);
      window.removeEventListener("offline", updateOnlineStatus);
    };
  }, [
    setAppInfo,
    setBridgeCapabilities,
    setBridgeReady,
    setColorModeState,
    setInitializing,
    setLanguage,
    setLastBridgeError,
    setOffline,
    setPendingNavigation,
    setPlatformLabel,
    setSystemInfo,
  ]);

  useEffect(() => {
    (window as any).canGoBack = () => {
      const currentPath = window.location.hash.replace(/^#/, "") || "/";
      return (
        currentPath !== "/sessions" && currentPath !== "/" && history.length > 1
      );
    };

    return () => {
      delete (window as any).canGoBack;
    };
  }, []);

  // Preload gateway data (workers + sessions) after bootstrap completes.
  // Separate from bootstrap() so failures don't affect system initialization.
  useEffect(() => {
    if (isInitializing || authLoading || !isLoggedIn) return;
    let cancelled = false;

    const preloadGateway = async () => {
      try {
        const [workers, sessions] = await Promise.all([
          terminalBridge.listWorkers(),
          terminalBridge.listSessions(),
        ]);
        if (cancelled) return;
        setWorkers(workers);
        setSessions(sessions);
      } catch (e) {
        console.warn("[App] Failed to preload gateway state:", e);
      } finally {
        if (!cancelled) setGatewayLoaded(true);
      }
    };

    preloadGateway();
    return () => { cancelled = true; };
  }, [isInitializing, authLoading, isLoggedIn, setWorkers, setSessions, setGatewayLoaded]);

  const requireAuth = (Component: React.ComponentType<any>, props?: any) => {
    if (authLoading) {
      return (
        <div style={{
          display: "flex", justifyContent: "center", alignItems: "center",
          height: "100%", width: "100%",
          background: "var(--ion-background-color)",
        }}>
          <IonSpinner name="crescent" />
        </div>
      );
    }
    return isLoggedIn ? <Component {...(props ?? {})} /> : <LoginPage />;
  };

  return (
    <IonApp>
      <IonReactRouter history={history}>
        <AppLayout>
          <Redirect exact from="/" to="/sessions" />
          <Route exact path="/sessions" render={(props) => requireAuth(SessionsPage, props)} />
          <Route exact path="/sessions/:sessionId" render={(props) => requireAuth(TerminalSessionPage, props)} />
          <Route exact path="/workers" render={() => requireAuth(WorkersPage)} />
          <Route exact path="/activate" render={() => requireAuth(ActivatePage)} />
          <Route exact path="/settings" render={() => requireAuth(SettingsFeaturePage)} />
          <Route render={() => <Redirect to="/sessions" />} />
        </AppLayout>
      </IonReactRouter>
    </IonApp>
  );
}
