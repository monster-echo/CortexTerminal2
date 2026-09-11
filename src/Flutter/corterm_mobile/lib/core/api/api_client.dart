import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

/// 统一 HTTP 客户端：
/// - 自动附加 `Authorization: Bearer`
/// - 401 时先尝试 `POST /api/auth/refresh` 续期后重放请求，失败则抛 [UnauthorizedException]
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokenStore, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final token = tokenStore.token;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }, onError: (error, handler) async {
      final response = error.response;
      if (response?.statusCode != 401 || _isRefreshCall(response)) {
        handler.next(error);
        return;
      }
      try {
        await _refreshToken();
      } on UnauthorizedException {
        handler.next(error);
        return;
      }
      // 续期成功：重放原请求（替换新的 Bearer）。
      final options = error.requestOptions;
      options.headers['Authorization'] = 'Bearer ${tokenStore.token}';
      try {
        final replay = await _dio.fetch<dynamic>(options);
        handler.resolve(replay);
      } on DioException catch (e) {
        handler.next(e);
      }
    }));
  }

  static bool _isRefreshCall(Response<dynamic>? response) =>
      response?.requestOptions.uri.path.contains('/auth/refresh') ?? false;

  final String baseUrl;
  final TokenStore tokenStore;
  final Dio _dio;

  Future<void>? _refreshing;

  Future<void> _refreshToken() {
    // 单飞：并发 401 只触发一次 refresh。
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        options: Options(headers: {'Authorization': 'Bearer ${tokenStore.token}'}),
      );
      final token = res.data?['accessToken'] as String?;
      if (token == null || token.isEmpty) {
        throw const UnauthorizedException();
      }
      await tokenStore.saveToken(token);
    } on DioException {
      throw const UnauthorizedException();
    }
  }

  /// GET 并解析 JSON 列表。
  Future<List<dynamic>> getList(String path) async {
    final res = await _dio.get<List<dynamic>>(path);
    return res.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> getMap(String path, {Map<String, dynamic>? query}) async {
    final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
    return res.data ?? const {};
  }

  Future<Map<String, dynamic>> postMap(String path, Object? body) async {
    final res = await _dio.post<Map<String, dynamic>>(path, data: body);
    return res.data ?? const {};
  }

  /// POST 纯文本 body（如头像 base64，MAUI 同款 text/plain）。
  Future<Map<String, dynamic>> postText(String path, String body) async {
    final res = await _dio.post<Map<String, dynamic>>(path, data: body,
        options: Options(headers: {'Content-Type': 'text/plain'}));
    return res.data ?? const {};
  }

  Future<Map<String, dynamic>> putMap(String path, Object? body) async {
    final res = await _dio.put<Map<String, dynamic>>(path, data: body);
    return res.data ?? const {};
  }

  Future<Map<String, dynamic>> patch(String path, Object? body) async {
    final res = await _dio.patch<Map<String, dynamic>>(path, data: body);
    return res.data ?? const {};
  }

  Future<void> delete(String path) async {
    await _dio.delete<void>(path);
  }

  /// 把 DioException 归一为 [ApiException] / [RateLimitedException]，其余原样抛出。
  static Never throwFor(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    String? serverMessage;
    if (data is Map<String, dynamic>) {
      serverMessage = data['error'] as String? ?? data['detail'] as String?;
      final retryAfter = data['retryAfter'];
      if (code == 429 && retryAfter is num) {
        throw RateLimitedException(retryAfter.toInt());
      }
    }
    throw ApiException(code ?? 0, serverMessage: serverMessage);
  }

  void dispose() => _dio.close();
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: ref.watch(appConfigProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});
