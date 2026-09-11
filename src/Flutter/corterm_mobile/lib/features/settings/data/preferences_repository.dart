import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// 服务端 scrollback 配额（对齐 Gateway GET/PUT /api/me/preferences）。
/// 该值控制 Worker 端重放窗口大小；客户端 xterm 缓冲恒为 64000 行（MAUI 同款）。
class ScrollbackPreference {
  ScrollbackPreference({required this.maxBytes, required this.maxAllowedBytes});

  final int maxBytes;
  final int maxAllowedBytes;

  factory ScrollbackPreference.fromJson(Map<String, dynamic> json) =>
      ScrollbackPreference(
        maxBytes: (json['scrollbackMaxBytes'] as num).toInt(),
        maxAllowedBytes: (json['scrollbackMaxAllowedBytes'] as num?)?.toInt() ?? 5242880,
      );
}

class PreferencesRepository {
  PreferencesRepository(this._client);

  final ApiClient _client;

  Future<ScrollbackPreference> get() async {
    final json = await _client.getMap('/api/me/preferences');
    return ScrollbackPreference.fromJson(json);
  }

  Future<void> updateScrollback({required int maxBytes}) async {
    try {
      await _client.putMap('/api/me/preferences', {'scrollbackMaxBytes': maxBytes});
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
    (ref) => PreferencesRepository(ref.watch(apiClientProvider)));

final scrollbackPreferenceProvider = FutureProvider<ScrollbackPreference>((ref) {
  return ref.watch(preferencesRepositoryProvider).get();
});
