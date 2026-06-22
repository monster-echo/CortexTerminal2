/**
 * @file AuthError.ets
 * @brief Typed auth error with kind discriminator.
 *
 * ApiService rejects with AuthError when the backend returns a well-known
 * auth-related error code (e.g. CAPTCHA_REQUIRED). UI layers can branch on
 * `kind` instead of fragile string matching on `message`.
 */
export class AuthErrorKind {
  static readonly CAPTCHA_REQUIRED: string = 'CAPTCHA_REQUIRED'
  static readonly UNKNOWN: string = 'UNKNOWN'
}

export class AuthError extends Error {
  kind: string
  statusCode: number

  constructor(kind: string, message: string, statusCode: number = 0) {
    super(message)
    this.name = 'AuthError'
    this.kind = kind
    this.statusCode = statusCode
  }
}
