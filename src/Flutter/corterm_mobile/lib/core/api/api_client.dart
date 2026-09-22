import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

  // ---- 统一响应形状校验 ----
  // dio 泛型（get<List<T>>) 在响应非 JSON 时会抛出晦涩的
  // "type 'String' is not a subtype of type 'List<dynamic>?'"。改为统一
  // 动态解析 + 显式校验，两端（Flutter/ArkTS）报同一句错误文案。

  /// 网关响应不是有效 JSON 的统一文案（两端保持一致）。
  static const String badJsonMessage = '网关响应不是有效 JSON（网关可能版本过旧）';

  Never _throwBadJson(String method, String path) =>
      throw ApiException(0, serverMessage: '$badJsonMessage：$method $path');

  /// GET 并解析 JSON 列表。
  Future<List<dynamic>> getList(String path) async {
    final data = (await _dio.get<dynamic>(path)).data;
    if (data is List<dynamic>) return data;
    throw _throwBadJson('GET', path);
  }

  Future<Map<String, dynamic>> getMap(String path, {Map<String, dynamic>? query}) async {
    final data = (await _dio.get<dynamic>(path, queryParameters: query)).data;
    if (data is Map<String, dynamic>) return data;
    throw _throwBadJson('GET', path);
  }

  Future<Map<String, dynamic>> postMap(String path, Object? body) async {
    final data = (await _dio.post<dynamic>(path, data: body)).data;
    if (data is Map<String, dynamic>) return data;
    throw _throwBadJson('POST', path);
  }

  /// POST 纯文本 body（如头像 base64，MAUI 同款 text/plain）。
  Future<Map<String, dynamic>> postText(String path, String body) async {
    final data = (await _dio.post<dynamic>(path, data: body,
        options: Options(headers: {'Content-Type': 'text/plain'}))).data;
    if (data is Map<String, dynamic>) return data;
    throw _throwBadJson('POST', path);
  }

  Future<Map<String, dynamic>> putMap(String path, Object? body) async {
    final data = (await _dio.put<dynamic>(path, data: body)).data;
    if (data is Map<String, dynamic>) return data;
    throw _throwBadJson('PUT', path);
  }

  Future<Map<String, dynamic>> patch(String path, Object? body) async {
    final data = (await _dio.patch<dynamic>(path, data: body)).data;
    if (data is Map<String, dynamic>) return data;
    throw _throwBadJson('PATCH', path);
  }

  Future<void> delete(String path) async {
    await _dio.delete<dynamic>(path);
  }

  /// 把 DioException 归一为 [ApiException] / [RateLimitedException]，其余原样抛出。
  static Never throwFor(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    String? serverMessage;
    if (data is Map<String, dynamic>) {
      serverMessage = data['error'] as String? ?? data['detail'] as String? ?? data['message'] as String?;
      final retryAfter = data['retryAfter'];
      if (code == 429 && retryAfter is num) {
        throw RateLimitedException(retryAfter.toInt());
      }
    }
    // 请求根本没到服务器（无 HTTP 响应）：web 上最常见的是浏览器跨域拦截
    // （网关未配置 CORS 允许当前来源），把根因讲清楚而不是只给 "Failed to fetch"。
    if (code == null) {
      final raw = e.message ?? e.error?.toString() ?? 'unknown';
      serverMessage = kIsWeb
          ? '请求未到达网关（浏览器跨域拦截或网络不可达）：$raw'
          : '无法连接网关：$raw';
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
