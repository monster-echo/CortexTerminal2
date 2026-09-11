/// 认证相关模型（对齐 Gateway `/api/auth/*`）。
library;

class AuthMethods {
  const AuthMethods({required this.methods});

  /// e.g. ["password", "phone", "github", ...]。本客户端 v1 只处理 password / phone。
  final List<String> methods;

  bool get hasPassword => methods.contains('password');
  bool get hasPhone => methods.contains('phone');

  factory AuthMethods.fromJson(Map<String, dynamic> json) {
    final raw = json['methods'];
    if (raw is! List) throw const FormatException('auth/methods: missing methods');
    return AuthMethods(methods: raw.cast<String>());
  }
}

/// 滑块验证码挑战（GET /api/auth/captcha/challenge）。
class CaptchaChallenge {
  const CaptchaChallenge({
    required this.id,
    required this.backgroundImage,
    required this.sliderImage,
    required this.y,
  });

  final String id;

  /// base64 图片（data URL 或裸 base64）。
  final String backgroundImage;
  final String sliderImage;
  final double y;

  factory CaptchaChallenge.fromJson(Map<String, dynamic> json) => CaptchaChallenge(
        id: json['id'] as String,
        backgroundImage: json['backgroundImage'] as String,
        sliderImage: json['sliderImage'] as String,
        y: (json['y'] as num).toDouble(),
      );
}

class LoginResult {
  const LoginResult({required this.accessToken, required this.username});

  final String accessToken;
  final String username;

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        accessToken: json['accessToken'] as String,
        username: json['username'] as String? ?? '',
      );
}
