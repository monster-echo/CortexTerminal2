import { nativeBridge } from "../bridge/nativeBridge";

export type ColorMode = "light" | "dark" | "system";

const STORAGE_KEY = "template.colorMode";
let systemThemeListener: ((e: MediaQueryListEvent) => void) | null = null;
let mediaQuery: MediaQueryList | null = null;

export function getSystemPreferredMode(): "light" | "dark" {
  if (
    typeof window === "undefined" ||
    typeof window.matchMedia !== "function"
  ) {
    return "light";
  }

  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

export function getStoredMode(): ColorMode | null {
  try {
    const value = window.localStorage.getItem(STORAGE_KEY);
    return value === "light" || value === "dark" || value === "system"
      ? value
      : null;
  } catch {
    return null;
  }
}

export function setStoredMode(mode: ColorMode) {
  try {
    window.localStorage.setItem(STORAGE_KEY, mode);
    nativeBridge.setStringValue("app.colorMode", mode).catch((e) => {
      console.warn("[colorMode] Failed to save theme to native preferences:", e);
    });
  } catch (e) {
    console.warn("[colorMode] Failed to persist color mode to localStorage:", e);
  }
}

function notifyHostTheme(mode: "light" | "dark") {
  nativeBridge.sendRaw({ type: "theme", mode });
}

function applyEffectiveTheme(mode: "light" | "dark") {
  const isDark = mode === "dark";
  document.documentElement.classList.toggle("ion-palette-dark", isDark);
  document.body.classList.toggle("dark", isDark);
  document.documentElement.style.colorScheme = isDark ? "dark" : "light";
  notifyHostTheme(mode);
}

export function applyColorMode(mode: ColorMode) {
  if (systemThemeListener && mediaQuery) {
    mediaQuery.removeEventListener("change", systemThemeListener);
    systemThemeListener = null;
    mediaQuery = null;
  }

  if (mode === "system") {
    applyEffectiveTheme(getSystemPreferredMode());
    mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    systemThemeListener = (event: MediaQueryListEvent) => {
      applyEffectiveTheme(event.matches ? "dark" : "light");
    };
    mediaQuery.addEventListener("change", systemThemeListener);
    return;
  }

  applyEffectiveTheme(mode);
}

export function initColorMode() {
  const mode = getStoredMode() ?? "system";
  applyColorMode(mode);
  return mode;
}
