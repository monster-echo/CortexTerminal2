import { Redirect, Route } from "react-router-dom";
import { IonApp, IonSpinner, setupIonicReact } from "@ionic/react";
import { IonReactRouter } from "@ionic/react-router";
import { createHashHistory } from "history";
import { useEffect } from "react";
import AppLayout from "./components/AppLayout";
import { nativeBridge } from "./bridge/nativeBridge";
import { transport } from "./bridge/runtime";
import HomeFeaturePage from "./features/home/HomeFeaturePage";
import MessagesFeaturePage from "./features/messages/MessagesFeaturePage";
import NotificationsFeaturePage from "./features/notifications/NotificationsFeaturePage";
import HapticsFeaturePage from "./features/haptics/HapticsFeaturePage";
import PhotosFeaturePage from "./features/photos/PhotosFeaturePage";
import CameraFeaturePage from "./features/camera/CameraFeaturePage";
import VideoFeaturePage from "./features/video/VideoFeaturePage";
import BridgeFeaturePage from "./features/bridge/BridgeFeaturePage";
import BridgeStreamFeaturePage from "./features/bridge/BridgeStreamFeaturePage";
import SettingsFeaturePage from "./features/settings/SettingsFeaturePage";
import PreferencesFeaturePage from "./features/preferences/PreferencesFeaturePage";
import ThemeFeaturePage from "./features/theme/ThemeFeaturePage";
import LoginPage from "./features/auth/LoginPage";
import SessionsPage from "./features/sessions/SessionsPage";
import TerminalSessionPage from "./features/sessions/TerminalSessionPage";
import WorkersPage from "./features/workers/WorkersPage";
import ActivatePage from "./features/activate/ActivatePage";
import ComponentsCatalogPage from "./features/components/ComponentsCatalogPage";
import ModalDemoPage from "./features/components/ModalDemoPage";
import PopoverDemoPage from "./features/components/PopoverDemoPage";
import ActionSheetDemoPage from "./features/components/ActionSheetDemoPage";
import AlertDemoPage from "./features/components/AlertDemoPage";
import LoadingDemoPage from "./features/components/LoadingDemoPage";
import ToastDemoPage from "./features/components/ToastDemoPage";
import AccordionDemoPage from "./features/components/AccordionDemoPage";
import FabDemoPage from "./features/components/FabDemoPage";
import TabsDemoPage from "./features/components/TabsDemoPage";
import NavDemoPage from "./features/components/NavDemoPage";
import GridDemoPage from "./features/components/GridDemoPage";
import SegmentDemoPage from "./features/components/SegmentDemoPage";
import RefresherDemoPage from "./features/components/RefresherDemoPage";
import InfiniteScrollDemoPage from "./features/components/InfiniteScrollDemoPage";
import SearchbarDemoPage from "./features/components/SearchbarDemoPage";
import ItemSlidingDemoPage from "./features/components/ItemSlidingDemoPage";
import ReorderDemoPage from "./features/components/ReorderDemoPage";
import InputDemoPage from "./features/components/InputDemoPage";
import TextareaDemoPage from "./features/components/TextareaDemoPage";
import SelectDemoPage from "./features/components/SelectDemoPage";
import RadioCheckboxDemoPage from "./features/components/RadioCheckboxDemoPage";
import DatetimeDemoPage from "./features/components/DatetimeDemoPage";
import RangeToggleDemoPage from "./features/components/RangeToggleDemoPage";
import ChipDemoPage from "./features/components/ChipDemoPage";
import ProgressDemoPage from "./features/components/ProgressDemoPage";
import AvatarThumbnailDemoPage from "./features/components/AvatarThumbnailDemoPage";
import SpinnerDemoPage from "./features/components/SpinnerDemoPage";
import {
  applyColorMode,
  getStoredMode,
  initColorMode,
  setStoredMode,
  type ColorMode,
} from "./theme/colorMode";
import { createFeatureDefinitions } from "./features/catalog/createFeatureCatalog";
import { useAppStore } from "./store/appStore";
import { useAuthStore } from "./store/authStore";
import { authBridge } from "./bridge/modules/authBridge";
import "./theme/variables.css";

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
  const colorMode = useAppStore((state) => state.colorMode);
  const setColorModeState = useAppStore((state) => state.setColorMode);
  const setPlatformLabel = useAppStore((state) => state.setPlatformLabel);
  const setBridgeReady = useAppStore((state) => state.setBridgeReady);
  const setBridgeCapabilities = useAppStore(
    (state) => state.setBridgeCapabilities,
  );
  const setSystemInfo = useAppStore((state) => state.setSystemInfo);
  const setAppInfo = useAppStore((state) => state.setAppInfo);
  const setPendingNavigation = useAppStore(
    (state) => state.setPendingNavigation,
  );
  const setFeatureDefinitions = useAppStore(
    (state) => state.setFeatureDefinitions,
  );
  const setOffline = useAppStore((state) => state.setOffline);
  const setLastBridgeError = useAppStore((state) => state.setLastBridgeError);
  const setInitializing = useAppStore((state) => state.setInitializing);
  const setLanguage = useAppStore((state) => state.setLanguage);
  const { isLoggedIn, isLoading: authLoading, setSession, clearSession, setLoading: setAuthLoading } = useAuthStore();

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
    setFeatureDefinitions(createFeatureDefinitions());

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
    setFeatureDefinitions,
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

  const updateColorMode = (mode: ColorMode) => {
    setStoredMode(mode);
    applyColorMode(mode);
    setColorModeState(mode);
  };

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
          <Route exact path="/home" render={(props) => requireAuth(HomeFeaturePage, props)} />
          <Route exact path="/messages" render={() => requireAuth(MessagesFeaturePage)} />
          <Route exact path="/notifications" render={() => requireAuth(NotificationsFeaturePage)} />
          <Route exact path="/haptics" render={() => requireAuth(HapticsFeaturePage)} />
          <Route exact path="/photos" render={() => requireAuth(PhotosFeaturePage)} />
          <Route exact path="/camera" render={() => requireAuth(CameraFeaturePage)} />
          <Route exact path="/video" render={() => requireAuth(VideoFeaturePage)} />
          <Route exact path="/bridge" render={() => requireAuth(BridgeFeaturePage)} />
          <Route exact path="/bridge/stream" render={() => requireAuth(BridgeStreamFeaturePage)} />
          <Route exact path="/preferences" render={() => requireAuth(PreferencesFeaturePage)} />
          <Route exact path="/theme" render={() =>
            requireAuth(ThemeFeaturePage, { colorMode, onColorModeChange: updateColorMode })
          } />
          <Route exact path="/settings" render={() => requireAuth(SettingsFeaturePage)} />
          <Route exact path="/components" render={() => requireAuth(ComponentsCatalogPage)} />
          <Route exact path="/components/modal" render={() => requireAuth(ModalDemoPage)} />
          <Route exact path="/components/popover" render={() => requireAuth(PopoverDemoPage)} />
          <Route exact path="/components/action-sheet" render={() => requireAuth(ActionSheetDemoPage)} />
          <Route exact path="/components/alert" render={() => requireAuth(AlertDemoPage)} />
          <Route exact path="/components/loading" render={() => requireAuth(LoadingDemoPage)} />
          <Route exact path="/components/toast" render={() => requireAuth(ToastDemoPage)} />
          <Route exact path="/components/accordion" render={() => requireAuth(AccordionDemoPage)} />
          <Route exact path="/components/fab" render={() => requireAuth(FabDemoPage)} />
          <Route exact path="/components/tabs" render={() => requireAuth(TabsDemoPage)} />
          <Route exact path="/components/nav" render={() => requireAuth(NavDemoPage)} />
          <Route exact path="/components/grid" render={() => requireAuth(GridDemoPage)} />
          <Route exact path="/components/segment" render={() => requireAuth(SegmentDemoPage)} />
          <Route exact path="/components/refresher" render={() => requireAuth(RefresherDemoPage)} />
          <Route exact path="/components/infinite-scroll" render={() => requireAuth(InfiniteScrollDemoPage)} />
          <Route exact path="/components/searchbar" render={() => requireAuth(SearchbarDemoPage)} />
          <Route exact path="/components/item-sliding" render={() => requireAuth(ItemSlidingDemoPage)} />
          <Route exact path="/components/reorder" render={() => requireAuth(ReorderDemoPage)} />
          <Route exact path="/components/input" render={() => requireAuth(InputDemoPage)} />
          <Route exact path="/components/textarea" render={() => requireAuth(TextareaDemoPage)} />
          <Route exact path="/components/select" render={() => requireAuth(SelectDemoPage)} />
          <Route exact path="/components/radio-checkbox" render={() => requireAuth(RadioCheckboxDemoPage)} />
          <Route exact path="/components/datetime" render={() => requireAuth(DatetimeDemoPage)} />
          <Route exact path="/components/range-toggle" render={() => requireAuth(RangeToggleDemoPage)} />
          <Route exact path="/components/chip" render={() => requireAuth(ChipDemoPage)} />
          <Route exact path="/components/progress" render={() => requireAuth(ProgressDemoPage)} />
          <Route exact path="/components/avatar-thumbnail" render={() => requireAuth(AvatarThumbnailDemoPage)} />
          <Route exact path="/components/spinner" render={() => requireAuth(SpinnerDemoPage)} />
          <Route render={() => <Redirect to="/sessions" />} />
        </AppLayout>
      </IonReactRouter>
    </IonApp>
  );
}
