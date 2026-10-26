/// P2P 打洞握手（io 实现）+ 通道装配。
///
/// 流程（规格 §1）：绑定 UDP socket → 在同一 socket 上 STUN Binding →
/// 循环 POST /api/transfers/{transferId}/punch（role=client）拿 peerEndpoint →
/// 50ms 探包窗口（"PT"+12B txid，探包不加密，按任意 txid 接受首包）→
/// 打通后进入 AES-GCM 可靠流模式（§3）。
///
/// Web 平台无 UDP socket，`p2p_stub.dart` 提供同签名 stub（file_repository 条件导入）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'p2p_channel.dart';
import 'p2p_crypto.dart';
import 'reliable_stream.dart';
import 'stun_client.dart';

/// 探包前缀（对齐 Worker `UdpPunch`）。
final Uint8List probePrefix = Uint8List.fromList('PT'.codeUnits);

/// 探包总长 = "PT" + 12B txid。
const int probeLength = 14;

/// 打通一条 P2P 通道。超时/STUN 失败/punch 被拒抛 [P2pException]。
///
/// [gatewayBaseUrl] = 现有 API base（punch POST 走网关）；[jwt] 与
/// X-Corterm-Transfer-Token 一并携带；[deadline] 内未打通即放弃（端点协商用 6s）。
Future<P2pChannel> openP2pChannel({
  required String gatewayBaseUrl,
  required String transferId,
  required String token,
  required String? jwt,
  String role = 'client',
  Duration deadline = const Duration(seconds: 6),
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  // RawDatagramSocket is single-subscription. Keep its one listener alive
  // across STUN, probe and encrypted-channel phases.
  final events = socket.asBroadcastStream();
  final start = DateTime.now();
  try {
    // 1. 同一 socket 上 STUN（NAT 反射地址即探包/punch 上报地址）。
    final reflected = await StunClient.discover(
      socket,
      events: events,
      timeout: deadline < const Duration(seconds: 2)
          ? deadline
          : const Duration(seconds: 2),
    );
    // deadline 覆盖全程（STUN 已消耗掉的部分从 punch 窗口里扣掉）。
    final punchDeadline = DateTime.now().add(
      deadline - DateTime.now().difference(start),
    );

    // 2. 循环 punch（2s 间隔）直到 ready 或 deadline。
    Uri? peer;
    while (true) {
      peer = await _punch(
        gatewayBaseUrl: gatewayBaseUrl,
        transferId: transferId,
        token: token,
        jwt: jwt,
        role: role,
        endpoint: '$reflected',
      );
      if (peer != null) break;
      final next = DateTime.now().add(const Duration(seconds: 2));
      final wait = next.isAfter(punchDeadline)
          ? punchDeadline.difference(DateTime.now())
          : const Duration(seconds: 2);
      if (wait <= Duration.zero) {
        throw const P2pException('p2p: punch not ready within deadline');
      }
      await Future<void>.delayed(wait);
    }

    // 3. 探包窗口：50ms 间隔互发 "PT"+txid，收到任意探包即打通。
    final peerEndpoint = peer;
    final txid = StunClient.randomTxid();
    final probe = BytesBuilder()
      ..add(probePrefix)
      ..add(txid);
    final opened = Completer<void>();
    Timer? probeTimer;
    final sub = events.listen((event) {
      if (opened.isCompleted) return;
      final dg = socket.receive();
      if (dg == null) return;
      if (dg.data.length == probeLength &&
          dg.data[0] == probePrefix[0] &&
          dg.data[1] == probePrefix[1]) {
        opened.complete();
      }
      // 打通前的加密包（对端先于我们收到探包）忽略，等双向打通后重传兜底。
    });
    try {
      final peerAddr = InternetAddress(peerEndpoint.host);
      probeTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        socket.send(probe.toBytes(), peerAddr, peerEndpoint.port);
      });
      // §1.5：10s 无回包放弃；受外层 deadline 约束取较早者。
      await opened.future.timeout(const Duration(seconds: 10));
    } finally {
      probeTimer?.cancel();
      sub.cancel();
    }

    // 4. 装配加密可靠流通道。
    final cipher = P2pCipher.fromToken(token: token, transferId: transferId);
    final stream = ReliableStream(
      send: (frame) async {
        final packet = await cipher.seal(frame);
        socket.send(
          packet,
          InternetAddress(peerEndpoint.host),
          peerEndpoint.port,
        );
      },
    );
    StreamSubscription<RawSocketEvent>? channelSub;
    final channel = P2pChannel(
      cipher: cipher,
      stream: stream,
      onClose: () {
        channelSub?.cancel();
        socket.close();
      },
    );
    channelSub = events.listen((event) async {
      final dg = socket.receive();
      if (dg == null) return;
      if (dg.data.length == probeLength &&
          dg.data[0] == probePrefix[0] &&
          dg.data[1] == probePrefix[1]) {
        return; // 打通后的冗余探包。
      }
      await channel.handlePacket(Uint8List.fromList(dg.data));
    });
    return channel;
  } on Exception catch (e) {
    socket.close();
    if (e is P2pException) rethrow;
    throw P2pException('p2p: $e');
  }
}

/// POST /api/transfers/{transferId}/punch。ready=true 时返回 peerEndpoint，否则 null。
Future<Uri?> _punch({
  required String gatewayBaseUrl,
  required String transferId,
  required String token,
  required String? jwt,
  required String role,
  required String endpoint,
}) async {
  final client = HttpClient();
  try {
    final base = Uri.parse(gatewayBaseUrl);
    final req = await client.postUrl(
      base.replace(
        path:
            '${base.path.isEmpty ? '' : base.path}/api/transfers/$transferId/punch',
      ),
    );
    req.headers.set('Content-Type', 'application/json');
    if (jwt != null && jwt.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer $jwt');
    }
    req.headers.set('X-Corterm-Transfer-Token', token);
    req.add(utf8.encode(jsonEncode({'role': role, 'endpoint': endpoint})));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw P2pException('p2p: punch POST ${res.statusCode}');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['ready'] != true) return null;
    final peer = json['peerEndpoint'] as String?;
    if (peer == null || peer.isEmpty) {
      throw const P2pException('p2p: ready without peerEndpoint');
    }
    final i = peer.lastIndexOf(':');
    return Uri(
      scheme: 'udp',
      host: peer.substring(0, i),
      port: int.parse(peer.substring(i + 1)),
    );
  } finally {
    client.close(force: true);
  }
}

/// 供测试/调试生成探包。
Uint8List buildProbe(Uint8List txid) {
  if (txid.length != probeLength - probePrefix.length) {
    throw ArgumentError('txid must be 12B');
  }
  final b = BytesBuilder()
    ..add(probePrefix)
    ..add(txid);
  return b.toBytes();
}
