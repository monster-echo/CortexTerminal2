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
} from "../../schemas/bridgeSchema";

export const authBridge = {
  sendPhoneCode: (phone: string): Promise<{ success: boolean }> =>
    invoke("SendPhoneCodeAsync", PhoneSendCodeResponseSchema, [phone]),

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
};
