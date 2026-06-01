import { SuccessResponseSchema } from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

export const analyticsBridge = {
  trackEvent: (eventName: string, parameters?: Record<string, unknown>) =>
    invoke("TrackAnalyticsEventAsync", SuccessResponseSchema, [
      eventName,
      parameters ?? null,
    ]),
  setUserId: (userId: string) =>
    invoke("SetAnalyticsUserIdAsync", SuccessResponseSchema, [userId]),
};
