import {
  type AppInfoSummary,
  type BinaryTransferResult,
  type BridgeCapabilities,
  type NativeMediaAsset,
  type PendingNavigationState,
  type PreferenceEntry,
  type PlatformInfo,
  type SuccessResponse,
  type SystemInfo,
  type TextInteropResult,
} from "../schemas/bridgeSchema";
import { authBridge } from "./modules/authBridge";
import { deviceBridge } from "./modules/deviceBridge";
import { feedbackBridge } from "./modules/feedbackBridge";
import { infoBridge } from "./modules/infoBridge";
import { interopBridge } from "./modules/interopBridge";
import { integrationBridge } from "./modules/integrationBridge";
import { preferencesBridge } from "./modules/preferencesBridge";
import { sendRaw } from "./runtime";

export type {
  AppInfoSummary,
  BinaryTransferResult,
  BridgeCapabilities,
  NativeMediaAsset,
  PendingNavigationState,
  PreferenceEntry,
  PlatformInfo,
  SuccessResponse,
  SystemInfo,
  TextInteropResult,
};

export const nativeBridge = {
  sendRaw,
  ...authBridge,
  ...infoBridge,
  ...preferencesBridge,
  ...feedbackBridge,
  ...integrationBridge,
  ...interopBridge,
  ...deviceBridge,
};
