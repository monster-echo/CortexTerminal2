/// P2P 打洞 — Web 平台 stub（无 UDP socket）。签名与 p2p_transfer.dart 一致，
/// 由 file_repository 条件导入。抛 [P2pException] 走规格 §5 的端点回落。
library;

import 'p2p_channel.dart';

Future<P2pChannel> openP2pChannel({
  required String gatewayBaseUrl,
  required String transferId,
  required String token,
  required String? jwt,
  String role = 'client',
  Duration deadline = const Duration(seconds: 6),
}) async {
  throw const P2pException('p2p: UDP 打洞不支持当前平台（Web）');
}
