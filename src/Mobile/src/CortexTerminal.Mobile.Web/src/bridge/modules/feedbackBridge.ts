import { SuccessResponseSchema } from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

export const feedbackBridge = {
  showToast: (message: string) =>
    invoke("ShowToastAsync", SuccessResponseSchema, [message]),
  showToastWithDuration: (message: string, duration: "short" | "long") =>
    invoke("ShowToastWithDurationAsync", SuccessResponseSchema, [
      message,
      duration,
    ]),
  dismissToast: () => invoke("DismissToastAsync", SuccessResponseSchema),
  showSnackbar: (message: string) =>
    invoke("ShowSnackbarAsync", SuccessResponseSchema, [message]),
  showSnackbarWithOptions: (
    message: string,
    actionButtonText?: string | null,
    duration?: "short" | "long" | "indefinite",
  ) =>
    invoke("ShowSnackbarWithOptionsAsync", SuccessResponseSchema, [
      message,
      actionButtonText ?? null,
      duration ?? null,
    ]),
  dismissSnackbar: () => invoke("DismissSnackbarAsync", SuccessResponseSchema),
  haptics: (type: string) =>
    invoke("HapticsAsync", SuccessResponseSchema, [type]),
};
