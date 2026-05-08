import { z } from "zod";

export const BridgeCapabilitiesSchema = z.object({
  rawMessaging: z.boolean(),
  invokeDotNet: z.boolean(),
  nativeThemeSync: z.boolean(),
  pendingNavigation: z.boolean(),
  preferences: z.boolean(),
  haptics: z.boolean(),
  toast: z.boolean(),
  snackbar: z.boolean(),
  shareText: z.boolean(),
  composeEmail: z.boolean(),
  photoLibrary: z.boolean(),
  camera: z.boolean(),
  videoLibrary: z.boolean(),
  videoCapture: z.boolean(),
  appInfo: z.boolean(),
});

export const NativeMediaAssetSchema = z.object({
  fileName: z.string(),
  contentType: z.string(),
  fileSizeBytes: z.number(),
  source: z.string(),
  localUrl: z.string().nullable().optional(),
});

export const SystemInfoSchema = z.object({
  platform: z.string(),
  appVersion: z.string(),
  deviceModel: z.string(),
  manufacturer: z.string(),
  deviceName: z.string(),
  operatingSystem: z.string(),
});

export const PlatformInfoSchema = z.object({
  platform: z.string(),
});

export const SuccessResponseSchema = z.object({
  success: z.boolean(),
});

export const PendingNavigationStateSchema = z.object({
  hasPending: z.boolean(),
  route: z.string().nullable().optional(),
  payload: z.string().nullable().optional(),
});

export const AppInfoSummarySchema = z.object({
  appName: z.string(),
  appVersion: z.string(),
  packageIdentifier: z.string(),
  platform: z.string(),
  supportEmail: z.string(),
  privacyPolicyUrl: z.string(),
  termsOfServiceUrl: z.string(),
});

export const TextInteropResultSchema = z.object({
  source: z.string(),
  message: z.string(),
  length: z.number(),
  receivedAt: z.string(),
});

export const BinaryTransferResultSchema = z.object({
  source: z.string(),
  byteLength: z.number(),
  checksum: z.string(),
  base64: z.string(),
});

export const PreferenceEntrySchema = z.object({
  key: z.string(),
  title: z.string(),
  category: z.string(),
  description: z.string(),
  exists: z.boolean(),
  value: z.string(),
});

export const PreferenceEntriesSchema = z.array(PreferenceEntrySchema);

export const HelloResultSchema = z.object({
  message: z.string(),
});

export const GreetingResultSchema = z.object({
  greeting: z.string(),
  name: z.string(),
  language: z.string(),
  timestamp: z.string(),
  wordCount: z.number(),
});

export const AuthSessionSchema = z.object({
  token: z.string(),
  username: z.string(),
});

export const PhoneSendCodeResponseSchema = z.object({
  success: z.boolean(),
});

export const PhoneVerifyResponseSchema = z.object({
  success: z.boolean(),
  username: z.string().optional(),
});

export const OAuthStartResponseSchema = z.object({
  success: z.boolean(),
});

export const GuestLoginResponseSchema = z.object({
  success: z.boolean(),
  username: z.string(),
});

export type BridgeCapabilities = z.infer<typeof BridgeCapabilitiesSchema>;
export type NativeMediaAsset = z.infer<typeof NativeMediaAssetSchema>;
export type SystemInfo = z.infer<typeof SystemInfoSchema>;
export type PlatformInfo = z.infer<typeof PlatformInfoSchema>;
export type PendingNavigationState = z.infer<
  typeof PendingNavigationStateSchema
>;
export type AppInfoSummary = z.infer<typeof AppInfoSummarySchema>;
export type TextInteropResult = z.infer<typeof TextInteropResultSchema>;
export type BinaryTransferResult = z.infer<typeof BinaryTransferResultSchema>;
export type PreferenceEntry = z.infer<typeof PreferenceEntrySchema>;
export type SuccessResponse = z.infer<typeof SuccessResponseSchema>;
export type HelloResult = z.infer<typeof HelloResultSchema>;
export type GreetingResult = z.infer<typeof GreetingResultSchema>;
export type AuthSession = z.infer<typeof AuthSessionSchema>;
export type PhoneSendCodeResponse = z.infer<typeof PhoneSendCodeResponseSchema>;
export type PhoneVerifyResponse = z.infer<typeof PhoneVerifyResponseSchema>;
export type OAuthStartResponse = z.infer<typeof OAuthStartResponseSchema>;
export type GuestLoginResponse = z.infer<typeof GuestLoginResponseSchema>;
