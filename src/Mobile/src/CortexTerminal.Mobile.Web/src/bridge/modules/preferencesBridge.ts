import {
  PendingNavigationStateSchema,
  PreferenceEntriesSchema,
  SuccessResponseSchema,
} from "../../schemas/bridgeSchema";
import { z } from "zod";
import { invoke } from "../runtime";

export const preferencesBridge = {
  getStringValue: (key: string) =>
    invoke("GetStringValueAsync", z.string(), [key]),
  setStringValue: (key: string, value: string) =>
    invoke("SetStringValueAsync", SuccessResponseSchema, [key, value]),
  removeStringValue: (key: string) =>
    invoke("RemoveStringValueAsync", SuccessResponseSchema, [key]),
  getPreferenceEntries: () =>
    invoke("GetPreferenceEntriesAsync", PreferenceEntriesSchema),
  getPendingNavigation: () =>
    invoke("GetPendingNavigationAsync", PendingNavigationStateSchema),
  setPendingNavigation: (route: string, payload?: string) =>
    invoke("SetPendingNavigationAsync", SuccessResponseSchema, [
      route,
      payload ?? null,
    ]),
  clearPendingNavigation: () =>
    invoke("ClearPendingNavigationAsync", SuccessResponseSchema),
};
