import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 网络连通性变化流。消费方（app.dart）监听 offline → online 跳变触发重连。
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

bool isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);
