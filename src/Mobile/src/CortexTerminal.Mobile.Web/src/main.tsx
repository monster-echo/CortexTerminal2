import React from "react";
import { createRoot } from "react-dom/client";
import "./bridge/hybridwebview";
import "./i18n";
import App from "./App";
import { transport } from "./bridge/runtime";
import { initColorMode } from "./theme/colorMode";
import { analyticsBridge } from "./bridge/modules/analyticsBridge";
import { ErrorBoundary } from "./components/ErrorBoundary";

const container = document.getElementById("root");
const root = createRoot(container!);

const APP_START_TS = performance.now();

const sendAppReady = () => {
  try {
    transport.sendRaw({ type: "appReady" });
  } catch (error) {
    console.warn("Failed to send appReady", error);
  }
  analyticsBridge.trackTiming("app_start", performance.now() - APP_START_TS, { phase: "cold" });
};

const sendAppInit = () => {
  try {
    transport.sendRaw({ type: "appInit" });
  } catch (error) {
    console.warn("Failed to send appInit", error);
  }
};

const renderApp = (initialData?: unknown) => {
  root.render(
    <ErrorBoundary>
      <App initialData={initialData as { platform?: string } | undefined} />
    </ErrorBoundary>,
  );
};

const initDataHandler = (data: unknown) => {
  if (!data || typeof data !== "object") return;
  const typed = data as { type?: string; payload?: unknown };
  if (typed.type !== "initData") return;

  (window as any).initData = typed.payload;

  // Apply theme before rendering so React's first paint has correct background
  initColorMode();

  renderApp(typed.payload);

  // Wait for a frame to ensure the WebView has painted before revealing content
  requestAnimationFrame(() => {
    sendAppReady();
  });
};

const unsubscribe = transport.onMessage(initDataHandler);
sendAppInit();
