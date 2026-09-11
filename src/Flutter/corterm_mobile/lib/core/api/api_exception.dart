/// API 层异常。全部显式抛出，由 UI 呈现（禁止静默吞错）。
library;

/// 非 2xx 响应。`serverMessage` 为 Gateway `{ "error": "..." }` 中的内容。
class ApiException implements Exception {
  ApiException(this.statusCode, {this.serverMessage});

  final int statusCode;
  final String? serverMessage;

  /// Gateway 约定的错误码（如 CAPTCHA_REQUIRED）。
  String? get errorCode => serverMessage;

  bool get isCaptchaRequired => serverMessage == 'CAPTCHA_REQUIRED';

  @override
  String toString() =>
      'ApiException($statusCode${serverMessage == null ? '' : ', $serverMessage'})';
}

/// 登录/手机验证码被限流（429 `{error, retryAfter}`）。
class RateLimitedException implements Exception {
  RateLimitedException(this.retryAfterSeconds);

  final int retryAfterSeconds;
}

/// Token 失效且刷新失败，需要重新登录。
class UnauthorizedException implements Exception {
  const UnauthorizedException();
  @override
  String toString() => 'UnauthorizedException';
}
