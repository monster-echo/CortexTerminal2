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
  captchaRequired: z.boolean().optional(),
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

export const VerifyActivationCodeResponseSchema = z.object({
  confirmed: z.boolean(),
});

export const PasswordLoginResponseSchema = z.object({
  success: z.boolean(),
  username: z.string().optional(),
  captchaRequired: z.boolean().optional(),
});

export const AltchaChallengeResponseSchema = z.object({
  json: z.string(),
});

export const CaptchaChallengeResponseSchema = z.object({
  id: z.string(),
  backgroundImage: z.string(),
  sliderImage: z.string(),
  y: z.number(),
});

export const CaptchaVerifyResponseSchema = z.object({
  captchaToken: z.string(),
});

export const AuthMethodsResponseSchema = z.object({
  methods: z.array(z.string()),
});

export const DeleteAccountResponseSchema = z.object({
  success: z.boolean(),
});

export const ChangePasswordResponseSchema = z.object({
  success: z.boolean(),
});

export const UserProfileResponseSchema = z.object({
  username: z.string(),
  hasPassword: z.boolean(),
  avatarUrl: z.string().nullable().optional(),
});

export const UpdateAvatarResponseSchema = z.object({
  success: z.boolean(),
  avatarUrl: z.string().nullable().optional(),
});

export const HasClipboardTextSchema = z.object({
  hasText: z.boolean(),
});

export const ReadClipboardTextSchema = z.object({
  text: z.string().nullable(),
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
export type VerifyActivationCodeResponse = z.infer<typeof VerifyActivationCodeResponseSchema>;
export type PasswordLoginResponse = z.infer<typeof PasswordLoginResponseSchema>;
export type AltchaChallengeResponse = z.infer<typeof AltchaChallengeResponseSchema>;
export type CaptchaChallengeResponse = z.infer<typeof CaptchaChallengeResponseSchema>;
export type CaptchaVerifyResponse = z.infer<typeof CaptchaVerifyResponseSchema>;
export type AuthMethodsResponse = z.infer<typeof AuthMethodsResponseSchema>;
export type DeleteAccountResponse = z.infer<typeof DeleteAccountResponseSchema>;
export type ChangePasswordResponse = z.infer<typeof ChangePasswordResponseSchema>;
export type UserProfileResponse = z.infer<typeof UserProfileResponseSchema>;
export type UpdateAvatarResponse = z.infer<typeof UpdateAvatarResponseSchema>;
