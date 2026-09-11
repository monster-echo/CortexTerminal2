import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT 安全存储（§60：Token 必须使用 Secure Storage）。
class TokenStore {
  TokenStore(this._storage);

  static const _kToken = 'auth.access_token';
  static const _kUsername = 'auth.username';

  final FlutterSecureStorage _storage;

  String? _cachedToken;
  String? _cachedUsername;

  String? get token => _cachedToken;
  String? get username => _cachedUsername;

  Future<void> load() async {
    _cachedToken = await _storage.read(key: _kToken);
    _cachedUsername = await _storage.read(key: _kUsername);
  }

  Future<void> save({required String token, required String username}) async {
    _cachedToken = token;
    _cachedUsername = username;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUsername, value: username);
  }

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _kToken, value: token);
  }

  Future<void> clear() async {
    _cachedToken = null;
    _cachedUsername = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUsername);
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) {
  const storage = FlutterSecureStorage();
  return TokenStore(storage);
});
