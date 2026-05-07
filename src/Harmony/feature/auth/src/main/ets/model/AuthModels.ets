/**
 * @file AuthModels.ets
 * @brief Data transfer objects for auth feature
 *
 * Defines request and response models for phone login,
 * OAuth, and token management.
 */

/**
 * Request to send a phone verification code.
 * Backend expects camelCase: { "phone": "..." }
 */
@Observed
export class PhoneSendCodeRequest {
  phone: string = ''
}

/**
 * Request to verify a phone number with code.
 * Backend expects camelCase: { "phone": "...", "code": "..." }
 */
@Observed
export class PhoneVerifyRequest {
  phone: string = ''
  code: string = ''
}

/**
 * Response from phone verification.
 * Backend returns: { "accessToken": "...", "username": "..." }
 */
@Observed
export class PhoneVerifyResponse {
  accessToken: string = ''
  username: string = ''
}

/**
 * Stored token data for persistence.
 */
@Observed
export class TokenData {
  accessToken: string = ''
  refreshToken: string = ''
  expiresAt: number = 0
  tokenType: string = 'Bearer'
}

/**
 * User information returned from the API.
 */
@Observed
export class UserInfo {
  id: string = ''
  email: string = ''
  displayName: string = ''
  avatarUrl: string = ''
  phone: string = ''
  createdAt: string = ''
}

/**
 * Request for OAuth callback with authorization code.
 */
@Observed
export class OAuthCallbackRequest {
  code: string = ''
}

/**
 * Request for activating a worker.
 */
@Observed
export class WorkerActivateRequest {
  code: string = ''
}

/**
 * Request for refreshing an authentication token.
 */
@Observed
export class TokenRefreshRequest {
  refreshToken: string = ''
}
