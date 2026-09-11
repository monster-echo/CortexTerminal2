import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// 客服群组（QQ 群带号码，Telegram 群带链接）。
class SupportGroup {
  SupportGroup({
    required this.name,
    this.number,
    this.url,
    required this.qrCodeUrl,
  });

  final String name;
  final String? number;
  final String? url;
  final String qrCodeUrl;
}

/// 客服信息（对齐 Gateway GET /api/support/info，AllowAnonymous）。
class SupportInfo {
  SupportInfo({this.qqGroup, this.telegramGroup, required this.email});

  final SupportGroup? qqGroup;
  final SupportGroup? telegramGroup;
  final String email;
}

class SupportRepository {
  SupportRepository(this._client);

  final ApiClient _client;

  Future<SupportInfo> get() async {
    final json = await _client.getMap('/api/support/info');
    return SupportInfo(
      qqGroup: _parseGroup(json['qqGroup']),
      telegramGroup: _parseGroup(json['telegramGroup']),
      email: json['email'] as String? ?? '',
    );
  }

  SupportGroup? _parseGroup(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return SupportGroup(
      name: raw['name'] as String? ?? '',
      number: raw['number'] as String?,
      url: raw['url'] as String?,
      qrCodeUrl: raw['qrCodeUrl'] as String? ?? '',
    );
  }
}

final supportRepositoryProvider =
    Provider<SupportRepository>((ref) => SupportRepository(ref.watch(apiClientProvider)));

final supportInfoProvider = FutureProvider<SupportInfo>((ref) {
  return ref.watch(supportRepositoryProvider).get();
});
