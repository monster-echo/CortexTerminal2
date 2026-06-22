import { SuccessResponseSchema } from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

const fireAndForget = (fn: () => Promise<unknown>) => {
  fn().catch((e) => console.warn("[analytics]", e));
};

const MAX_MESSAGE_LENGTH = 200;

function truncate(value: string, max: number): string {
  if (value.length <= max) return value;
  return value.slice(0, max);
}

function hashString(value: string): string {
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    const chr = value.charCodeAt(i);
    hash = (hash << 5) - hash + chr;
    hash |= 0;
  }
  return (hash >>> 0).toString(16);
}

export interface PageViewParams {
  pageName: string;
  pagePath: string;
  routeTemplate: string;
}

export interface ErrorParams {
  source: "window.onerror" | "unhandledrejection" | "error_boundary" | "bootstrap";
  message: string;
  stackHash?: string;
  stack?: string;
}

export const analyticsBridge = {
  trackEvent: (eventName: string, parameters?: Record<string, unknown>) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      eventName,
      parameters ?? null,
    ]));
  },
  setUserId: (userId: string) => {
    fireAndForget(() => invoke("SetAnalyticsUserIdAsync", SuccessResponseSchema, [userId]));
  },
  setUserProperty: (name: string, value: string) => {
    fireAndForget(() => invoke("SetAnalyticsUserPropertyAsync", SuccessResponseSchema, [name, value]));
  },
  trackPageView: (params: PageViewParams) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "hybrid_page_view",
      {
        page_name: params.pageName,
        page_path: params.pagePath,
        page_route_template: params.routeTemplate,
      },
    ]));
  },
  trackTap: (elementId: string, routeTemplate: string) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "ui_tap",
      {
        element_id: elementId,
        page_route_template: routeTemplate,
      },
    ]));
  },
  trackInputFocus: (fieldId: string, routeTemplate: string) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "input_focus",
      {
        field_id: fieldId,
        page_route_template: routeTemplate,
      },
    ]));
  },
  trackInputBlur: (fieldId: string, routeTemplate: string, durationMs: number) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "input_blur",
      {
        field_id: fieldId,
        page_route_template: routeTemplate,
        duration_ms: Math.round(durationMs),
      },
    ]));
  },
  trackError: (params: ErrorParams) => {
    const stack = params.stack ?? "";
    const stackHash = params.stackHash ?? (stack ? hashString(stack) : "");
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "js_error",
      {
        error_source: params.source,
        message: truncate(params.message, MAX_MESSAGE_LENGTH),
        stack_hash: stackHash,
      },
    ]));
  },
  trackBridgeError: (callName: string, errorType: string, message: string) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "bridge_error",
      {
        call_name: callName,
        error_type: errorType,
        message: truncate(message, MAX_MESSAGE_LENGTH),
      },
    ]));
  },
  trackTerminalError: (sessionId: string, reason: string) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "terminal_error",
      {
        session_id: sessionId,
        reason,
      },
    ]));
  },
  trackTiming: (name: string, durationMs: number, params?: Record<string, unknown>) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      name,
      {
        duration_ms: Math.round(durationMs),
        ...(params ?? {}),
      },
    ]));
  },
  trackNetworkChange: (state: "online" | "offline", previousState: "online" | "offline") => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      "network_change",
      {
        network_state: state,
        previous_state: previousState,
      },
    ]));
  },
};
