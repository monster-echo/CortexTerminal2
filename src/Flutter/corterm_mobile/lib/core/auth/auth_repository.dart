import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/auth_models.dart';

/// 认证数据源：对齐 Gateway `/api/auth/*`（见 MAUI AuthService / Gateway Program.cs）。
class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<AuthMethods> methods() async {
    final json = await _client.getMap('/api/auth/methods');
    return AuthMethods.fromJson(json);
  }

  Future<CaptchaChallenge> captchaChallenge() async {
    final json = await _client.getMap('/api/auth/captcha/challenge');
    return CaptchaChallenge.fromJson(json);
  }

  Future<String> captchaVerify({required String id, required double x}) async {
    final json = await _client.postMap('/api/auth/captcha/verify', {'id': id, 'x': x});
    final token = json['captchaToken'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException(0, serverMessage: 'captcha verify returned no token');
    }
    return token;
  }

  /// 密码登录。403 CAPTCHA_REQUIRED 时抛 [ApiException]（isCaptchaRequired = true）。
  Future<LoginResult> passwordLogin(
      {required String username, required String password, String? captchaToken}) async {
    return _login(() => _client.postMap('/api/auth/password/login', {
          'username': username,
          'password': password,
          'captchaToken': ?captchaToken,
        }));
  }

  Future<void> sendPhoneCode({required String phone, String? captchaToken}) async {
    try {
      await _client.postMap('/api/auth/phone/send-code', {
        'phone': phone,
        'captchaToken': ?captchaToken,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<LoginResult> verifyPhoneCode({required String phone, required String code}) async {
    return _login(
        () => _client.postMap('/api/auth/phone/verify', {'phone': phone, 'code': code}));
  }

  /// Apple 原生登录：ASAuthorization 的 authorizationCode → gateway 换 JWT。
  /// gateway 端点：POST /api/auth/apple/native → {accessToken}（见 Program.cs）。
  Future<LoginResult> appleLogin({required String authorizationCode}) {
    return _login(
        () => _client.postMap('/api/auth/apple/native', {'code': authorizationCode}));
  }

  /// 设备流激活码确认（POST /api/auth/device-flow/verify）。
  /// 无效码 gateway 返回 400 {error: invalid_code}。
  Future<void> verifyActivationCode({required String userCode}) async {
    try {
      await _client.postMap('/api/auth/device-flow/verify', {'userCode': userCode});
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<LoginResult> _login(Future<Map<String, dynamic>> Function() call) async {
    try {
      final json = await call();
      return LoginResult.fromJson(json);
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _client.putMap('/api/me/password', {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _client.delete('/api/me/account');
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => AuthRepository(ref.watch(apiClientProvider)));
