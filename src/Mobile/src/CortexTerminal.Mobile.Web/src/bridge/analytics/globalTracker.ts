import { analyticsBridge } from "../modules/analyticsBridge";

let currentRouteTemplate = "";
let initialized = false;

const focusState = new Map<Element, { fieldId: string; startTs: number }>();

function findAnalyticsAncestor(target: EventTarget | null): { element: HTMLElement; id: string } | null {
  if (!(target instanceof Element)) return null;
  const matched = target.closest("[data-analytics-id]") as HTMLElement | null;
  if (!matched) return null;
  const id = matched.getAttribute("data-analytics-id");
  if (!id) return null;
  return { element: matched, id };
}

function onClick(event: MouseEvent): void {
  const hit = findAnalyticsAncestor(event.target);
  if (!hit) return;
  analyticsBridge.trackTap(hit.id, currentRouteTemplate);
}

function onFocusIn(event: FocusEvent): void {
  const hit = findAnalyticsAncestor(event.target);
  if (!hit) return;
  focusState.set(hit.element, {
    fieldId: hit.id,
    startTs: performance.now(),
  });
  analyticsBridge.trackInputFocus(hit.id, currentRouteTemplate);
}

function onFocusOut(event: FocusEvent): void {
  const target = event.target;
  if (!(target instanceof Element)) return;
  const entry = focusState.get(target);
  if (!entry) return;
  focusState.delete(target);
  const duration = performance.now() - entry.startTs;
  analyticsBridge.trackInputBlur(entry.fieldId, currentRouteTemplate, duration);
}

function onError(event: ErrorEvent): void {
  analyticsBridge.trackError({
    source: "window.onerror",
    message: event.message || "unknown error",
    stack: event.error?.stack,
  });
}

function onUnhandledRejection(event: PromiseRejectionEvent): void {
  const reason = event.reason;
  const message = reason instanceof Error ? reason.message : String(reason);
  const stack = reason instanceof Error ? reason.stack : undefined;
  analyticsBridge.trackError({
    source: "unhandledrejection",
    message,
    stack,
  });
}

export function setRouteTemplate(template: string): void {
  currentRouteTemplate = template || "";
}

export function getCurrentRouteTemplate(): string {
  return currentRouteTemplate;
}

export function initGlobalAnalytics(): () => void {
  if (initialized) {
    return () => {};
  }
  initialized = true;

  document.addEventListener("click", onClick, true);
  document.addEventListener("focusin", onFocusIn, true);
  document.addEventListener("focusout", onFocusOut, true);
  window.addEventListener("error", onError);
  window.addEventListener("unhandledrejection", onUnhandledRejection);

  return () => {
    document.removeEventListener("click", onClick, true);
    document.removeEventListener("focusin", onFocusIn, true);
    document.removeEventListener("focusout", onFocusOut, true);
    window.removeEventListener("error", onError);
    window.removeEventListener("unhandledrejection", onUnhandledRejection);
    initialized = false;
  };
}
