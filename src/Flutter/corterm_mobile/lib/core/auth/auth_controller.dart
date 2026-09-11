import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_store.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.username});

  final AuthStatus status;
  final String? username;
}

/// 认证全局状态：启动时从 secure storage 恢复；登录成功写入；登出清除。
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._store) : super(const AuthState(status: AuthStatus.loading));

  final TokenStore _store;

  Future<void> restore() async {
    await _store.load();
    if (_store.token == null || _store.token!.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    state = AuthState(status: AuthStatus.authenticated, username: _store.username);
  }

  /// OAuth 回调只携带 token：从 JWT `sub` 解出用户名（MAUI AuthService 同款）。
  Future<void> loggedInFromToken(String token) async {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const FormatException('invalid JWT');
    }
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final username = payload['sub'] as String? ?? '';
    await loggedIn(token: token, username: username);
  }

  Future<void> loggedIn({required String token, required String username}) async {
    await _store.save(token: token, username: username);
    state = AuthState(status: AuthStatus.authenticated, username: username);
  }

  /// 刷新 token（ApiClient 续期成功后调用，保持缓存同步）。
  Future<void> tokenRefreshed(String token) => _store.saveToken(token);

  Future<void> logout() async {
    await _store.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(tokenStoreProvider));
});

/// OAuth 回调失败码（?error=...），登录页展示后自行清除。
final oauthLastErrorProvider = StateProvider<String?>((ref) => null);
