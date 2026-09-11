import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/auth/auth_controller.dart';
import 'core/storage/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // 启动时恢复认证状态（§58/§59）：有 token 直接进入已登录态。
  await container.read(authProvider.notifier).restore();

  _listenOauthLinks(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CortermApp(),
    ),
  );
}

/// OAuth 回调：`corterm.mobile://auth?token=<jwt>`（或 `?error=<code>`）。
/// 登录页发起系统浏览器授权，网关 302 回此 scheme。
void _listenOauthLinks(ProviderContainer container) {
  final links = AppLinks();
  StreamSubscription<Uri>? sub;
  sub = links.uriLinkStream.listen((uri) {
    if (uri.scheme != 'corterm.mobile' || uri.host != 'auth') return;
    final token = uri.queryParameters['token'];
    final error = uri.queryParameters['error'];
    final auth = container.read(authProvider.notifier);
    if (token != null && token.isNotEmpty) {
      unawaited(auth.loggedInFromToken(token));
    } else if (error != null) {
      // 无 UI 上下文：失败时保持未登录态，登录页仍在前台，用户可直接重试。
      container.read(oauthLastErrorProvider.notifier).state = error;
    }
    unawaited(sub?.cancel());
  });
}
