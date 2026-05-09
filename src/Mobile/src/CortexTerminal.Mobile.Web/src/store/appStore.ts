import { create } from "zustand";
import i18n from "../i18n";
import { nativeBridge } from "../bridge/nativeBridge";
import type {
  AppInfoSummary,
  BridgeCapabilities,
  PendingNavigationState,
  SystemInfo,
} from "../schemas/bridgeSchema";
import type { ColorMode } from "../theme/colorMode";
import type { FeatureDefinition } from "../schemas/featureSchema";

export interface AppStoreState {
  platformLabel: string;
  colorMode: ColorMode;
  bridgeReady: boolean;
  isOffline: boolean;
  isInitializing: boolean;
  lastBridgeError: string | null;
  bridgeCapabilities: BridgeCapabilities | null;
  systemInfo: SystemInfo | null;
  appInfo: AppInfoSummary | null;
  pendingNavigation: PendingNavigationState | null;
  featureDefinitions: FeatureDefinition[];
  debugMode: boolean;
  setDebugMode: (value: boolean) => void;
  language: "en" | "zh";
  setLanguage: (value: "en" | "zh") => void;
  setPlatformLabel: (value: string) => void;
  setColorMode: (value: ColorMode) => void;
  setBridgeReady: (value: boolean) => void;
  setOffline: (value: boolean) => void;
  setInitializing: (value: boolean) => void;
  setLastBridgeError: (value: string | null) => void;
  setBridgeCapabilities: (value: BridgeCapabilities | null) => void;
  setSystemInfo: (value: SystemInfo | null) => void;
  setAppInfo: (value: AppInfoSummary | null) => void;
  setPendingNavigation: (value: PendingNavigationState | null) => void;
  setFeatureDefinitions: (value: FeatureDefinition[]) => void;
}

export const useAppStore = create<AppStoreState>((set) => ({
  platformLabel: "web",
  colorMode: "system",
  bridgeReady: false,
  isOffline: typeof navigator !== "undefined" ? !navigator.onLine : false,
  isInitializing: true,
  lastBridgeError: null,
  bridgeCapabilities: null,
  systemInfo: null,
  appInfo: null,
  pendingNavigation: null,
  featureDefinitions: [],
  debugMode: false,
  setDebugMode: (debugMode) => set({ debugMode }),
  language: (typeof localStorage !== "undefined" && (localStorage.getItem("lang") as "en" | "zh")) || "zh",
  setLanguage: (language) => {
    localStorage.setItem("lang", language);
    nativeBridge.setStringValue("app.language", language).catch((e) => {
      console.warn("[settings] Failed to save language to native preferences:", e);
    });
    i18n.changeLanguage(language);
    set({ language });
  },
  setPlatformLabel: (platformLabel) => set({ platformLabel }),
  setColorMode: (colorMode) => set({ colorMode }),
  setBridgeReady: (bridgeReady) => set({ bridgeReady }),
  setOffline: (isOffline) => set({ isOffline }),
  setInitializing: (isInitializing) => set({ isInitializing }),
  setLastBridgeError: (lastBridgeError) => set({ lastBridgeError }),
  setBridgeCapabilities: (bridgeCapabilities) => set({ bridgeCapabilities }),
  setSystemInfo: (systemInfo) => set({ systemInfo }),
  setAppInfo: (appInfo) => set({ appInfo }),
  setPendingNavigation: (pendingNavigation) => set({ pendingNavigation }),
  setFeatureDefinitions: (featureDefinitions) => set({ featureDefinitions }),
}));
