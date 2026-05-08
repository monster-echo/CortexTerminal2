import {
  AppInfoSummarySchema,
  BridgeCapabilitiesSchema,
  PlatformInfoSchema,
  SystemInfoSchema,
} from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

export const infoBridge = {
  getCapabilities: () =>
    invoke("GetBridgeCapabilitiesAsync", BridgeCapabilitiesSchema),
  getPlatformInfo: () => invoke("GetPlatformInfoAsync", PlatformInfoSchema),
  getSystemInfo: () => invoke("GetSystemInfoAsync", SystemInfoSchema),
  getAppInfo: () => invoke("GetAppInfoSummaryAsync", AppInfoSummarySchema),
};
