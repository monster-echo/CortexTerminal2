import React from "react";
import { createRoot } from "react-dom/client";
import "./bridge/hybridwebview";
import "./i18n";
import App from "./App";
import { transport } from "./bridge/runtime";

const container = document.getElementById("root");
const root = createRoot(container!);

const sendAppReady = () => {
  try {
    transport.sendRaw({ type: "appReady" });
  } catch (error) {
    console.warn("Failed to send appReady", error);
  }
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
    <App initialData={initialData as { platform?: string } | undefined} />,
  );
};

const initDataHandler = (data: unknown) => {
  if (!data || typeof data !== "object") return;
  const typed = data as { type?: string; payload?: unknown };
  if (typed.type !== "initData") return;

  (window as any).initData = typed.payload;
  renderApp(typed.payload);
  sendAppReady();
};

const unsubscribe = transport.onMessage(initDataHandler);
sendAppInit();
