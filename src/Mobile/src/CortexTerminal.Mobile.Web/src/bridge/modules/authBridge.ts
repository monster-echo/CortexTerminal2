import { invoke } from "../runtime";
import {
  AuthSessionSchema,
  type AuthSession,
  PhoneSendCodeResponseSchema,
  PhoneVerifyResponseSchema,
  type PhoneVerifyResponse,
  OAuthStartResponseSchema,
  GuestLoginResponseSchema,
  SuccessResponseSchema,
  VerifyActivationCodeResponseSchema,
  PasswordLoginResponseSchema,
  type PasswordLoginResponse,
  AltchaChallengeResponseSchema,
  DeleteAccountResponseSchema,
  ChangePasswordResponseSchema,
  UserProfileResponseSchema,
  type UserProfileResponse,
  UpdateAvatarResponseSchema,
} from "../../schemas/bridgeSchema";

export const authBridge = {
  getAltchaChallenge: (): Promise<{ json: string }> =>
    invoke("GetAltchaChallengeAsync", AltchaChallengeResponseSchema),

  sendPhoneCode: (phone: string, altchaPayload: string): Promise<{ success: boolean }> =>
    invoke("SendPhoneCodeAsync", PhoneSendCodeResponseSchema, [phone, altchaPayload]),

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

  loginWithPassword: (username: string, password: string): Promise<PasswordLoginResponse> =>
    invoke("LoginWithPasswordAsync", PasswordLoginResponseSchema, [username, password]),

  deleteAccount: (): Promise<{ success: boolean }> =>
    invoke("DeleteAccountAsync", DeleteAccountResponseSchema),

  setPassword: (currentPassword: string | null, newPassword: string): Promise<{ success: boolean }> =>
    invoke("SetPasswordAsync", ChangePasswordResponseSchema, [currentPassword, newPassword]),

  getProfile: (): Promise<UserProfileResponse | null> =>
    invoke("GetProfileAsync", UserProfileResponseSchema.nullable()),

  updateAvatar: (base64Image: string): Promise<{ success: boolean; avatarUrl?: string | null }> =>
    invoke("UpdateAvatarAsync", UpdateAvatarResponseSchema, [base64Image]),
};
