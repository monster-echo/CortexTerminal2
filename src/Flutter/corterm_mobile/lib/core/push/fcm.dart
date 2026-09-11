import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 推送总开关：纯构建期配置。gateway 的 device-token 上报端点
/// （POST /api/me/push-tokens，后端配合项 #3）交付前保持关闭——
/// 不做运行时静默跳过，未开启就不初始化任何 FCM 逻辑。
///
/// 开启方式：`--dart-define=CORTERM_ENABLE_PUSH=true`
const _pushEnabled =
    bool.fromEnvironment('CORTERM_ENABLE_PUSH', defaultValue: false);

/// FCM token 获取（客户端侧已就绪；上报链路等后端端点交付后接入）。
class FcmTokenProvider {
  FcmTokenProvider(this._enabled);

  final bool _enabled;
  String? _token;

  bool get enabled => _enabled;

  /// 未启用或尚未获取时返回 null。
  String? get token => _token;

  Future<void> ensureToken() async {
    if (!_enabled) {
      throw StateError('FCM disabled: build with --dart-define=CORTERM_ENABLE_PUSH=true');
    }
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('notification permission denied');
    }
    _token = await FirebaseMessaging.instance.getToken();
  }
}

final fcmTokenProvider = Provider<FcmTokenProvider>((ref) => FcmTokenProvider(_pushEnabled));
