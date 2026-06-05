import { SuccessResponseSchema } from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

const fireAndForget = (fn: () => Promise<unknown>) => {
  fn().catch((e) => console.warn("[analytics]", e));
};

export const analyticsBridge = {
  trackEvent: (eventName: string, parameters?: Record<string, unknown>) => {
    fireAndForget(() => invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      eventName,
      parameters ?? null,
    ]));
  },
  setScreen: (screenName: string, screenClass?: string) => {
    fireAndForget(() => invoke("SetAnalyticsScreenAsync", SuccessResponseSchema, [
      screenName,
      screenClass ?? null,
    ]));
  },
  setUserId: (userId: string) => {
    fireAndForget(() => invoke("SetAnalyticsUserIdAsync", SuccessResponseSchema, [userId]));
  },
};
