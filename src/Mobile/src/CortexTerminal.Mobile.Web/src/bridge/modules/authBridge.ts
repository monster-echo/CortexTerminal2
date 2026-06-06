import { invoke } from "../runtime";
import {
  AuthSessionSchema,
  type AuthSession,
  PhoneSendCodeResponseSchema,
  type PhoneSendCodeResponse,
  PhoneVerifyResponseSchema,
  type PhoneVerifyResponse,
  OAuthStartResponseSchema,
  GuestLoginResponseSchema,
  SuccessResponseSchema,
  VerifyActivationCodeResponseSchema,
  PasswordLoginResponseSchema,
  type PasswordLoginResponse,
  CaptchaChallengeResponseSchema,
  type CaptchaChallengeResponse,
  CaptchaVerifyResponseSchema,
  type CaptchaVerifyResponse,
  AuthMethodsResponseSchema,
  type AuthMethodsResponse,
  DeleteAccountResponseSchema,
  ChangePasswordResponseSchema,
  UserProfileResponseSchema,
  type UserProfileResponse,
  UpdateAvatarResponseSchema,
} from "../../schemas/bridgeSchema";

export const authBridge = {
  getAvailableAuthMethods: (): Promise<AuthMethodsResponse> =>
    invoke("GetAvailableAuthMethodsAsync", AuthMethodsResponseSchema),

  getCaptchaChallenge: (): Promise<CaptchaChallengeResponse> =>
    invoke("GetCaptchaChallengeAsync", CaptchaChallengeResponseSchema),

  verifyCaptcha: (id: string, x: number): Promise<CaptchaVerifyResponse> =>
    invoke("VerifyCaptchaAsync", CaptchaVerifyResponseSchema, [id, x]),

  sendPhoneCode: (phone: string, captchaToken?: string | null): Promise<PhoneSendCodeResponse> =>
    invoke("SendPhoneCodeAsync", PhoneSendCodeResponseSchema, [phone, captchaToken ?? null]),

  verifyPhoneCode: (phone: string, code: string): Promise<PhoneVerifyResponse> =>
    invoke("VerifyPhoneCodeAsync", PhoneVerifyResponseSchema, [phone, code]),

  startOAuth: (provider: string): Promise<{ success: boolean }> =>
    invoke("StartOAuthAsync", OAuthStartResponseSchema, [provider]),

  getSession: (): Promise<AuthSession | null> =>
    invoke("GetSessionAsync", AuthSessionSchema.nullable()),

  logout: (): Promise<{ success: boolean }> =>
    invoke("LogoutAsync", SuccessResponseSchema),

  guestLogin: (): Promise<{ success: boolean; username: string }> =>
    invoke("GuestLoginAsync", GuestLoginResponseSchema),

  verifyActivationCode: (userCode: string): Promise<{ confirmed: boolean }> =>
    invoke("VerifyActivationCodeAsync", VerifyActivationCodeResponseSchema, [userCode]),

  loginWithPassword: (username: string, password: string, captchaToken?: string | null): Promise<PasswordLoginResponse> =>
    invoke("LoginWithPasswordAsync", PasswordLoginResponseSchema, [username, password, captchaToken ?? null]),

  deleteAccount: (): Promise<{ success: boolean }> =>
    invoke("DeleteAccountAsync", DeleteAccountResponseSchema),

  setPassword: (currentPassword: string | null, newPassword: string): Promise<{ success: boolean }> =>
    invoke("SetPasswordAsync", ChangePasswordResponseSchema, [currentPassword, newPassword]),

  getProfile: (): Promise<UserProfileResponse | null> =>
    invoke("GetProfileAsync", UserProfileResponseSchema.nullable()),

  updateAvatar: (base64Image: string): Promise<{ success: boolean; avatarUrl?: string | null }> =>
    invoke("UpdateAvatarAsync", UpdateAvatarResponseSchema, [base64Image]),
};
