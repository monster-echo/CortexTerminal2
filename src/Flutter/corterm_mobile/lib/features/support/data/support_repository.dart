import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// 客服群组（带链接与二维码）。
class SupportGroup {
  SupportGroup({
    required this.name,
    required this.url,
    required this.qrCodeUrl,
  });

  final String name;
  final String url;
  final String qrCodeUrl;
}

/// 客服信息（对齐 Gateway GET /api/support/info，AllowAnonymous）。
/// 唯一客服渠道是飞书，QQ/Telegram 字段不再解析。
class SupportInfo {
  SupportInfo({this.feishuGroup});

  final SupportGroup? feishuGroup;
}

class SupportRepository {
  SupportRepository(this._client);

  final ApiClient _client;

  Future<SupportInfo> get() async {
    final json = await _client.getMap('/api/support/info');
    return SupportInfo(feishuGroup: _parseGroup(json['feishuGroup']));
  }

  SupportGroup? _parseGroup(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return SupportGroup(
      name: raw['name'] as String? ?? '',
      url: raw['url'] as String? ?? '',
      qrCodeUrl: raw['qrCodeUrl'] as String? ?? '',
    );
  }
}

final supportRepositoryProvider =
    Provider<SupportRepository>((ref) => SupportRepository(ref.watch(apiClientProvider)));

final supportInfoProvider = FutureProvider<SupportInfo>((ref) {
  return ref.watch(supportRepositoryProvider).get();
});
