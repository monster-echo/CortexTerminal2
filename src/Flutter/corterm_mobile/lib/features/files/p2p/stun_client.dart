/// RFC 5389 STUN Binding 编解码 + 在【既有】UDP socket 上做地址探测。
///
/// 协议见 docs/notes/p2p-protocol-spec.md §2（对齐 Worker `P2P/StunClient.cs`）：
/// 只 UDP、只 IPv4、只 XOR-MAPPED-ADDRESS（magic 0x2112A442）。
/// 必须复用打洞用的同一个 socket 发 Binding，否则 NAT 映射端口与探包端口不一致。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class StunAddress {
  const StunAddress({required this.host, required this.port});

  /// 反射后的公网 IPv4（点分十进制）。
  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

class StunClient {
  StunClient._();

  static const magicCookie = 0x2112A442;
  static const defaultServer = 'stun.l.google.com';
  static const defaultPort = 19302;

  static const _typeBindingRequest = 0x0001;
  static const _typeBindingResponse = 0x0101;
  static const _attrXorMappedAddress = 0x0020;

  /// 编码 Binding Request。header 20B：type(2) + length(2) + magic(4) + txid(12)。
  static Uint8List buildBindingRequest(Uint8List txid) {
    if (txid.length != 12) {
      throw ArgumentError.value(txid.length, 'txid', 'must be 12 bytes');
    }
    final b = BytesBuilder();
    b.addByte(_typeBindingRequest >> 8);
    b.addByte(_typeBindingRequest & 0xFF);
    b.addByte(0);
    b.addByte(0);
    b.addByte((magicCookie >> 24) & 0xFF);
    b.addByte((magicCookie >> 16) & 0xFF);
    b.addByte((magicCookie >> 8) & 0xFF);
    b.addByte(magicCookie & 0xFF);
    b.add(txid);
    return b.toBytes();
  }

  static Uint8List randomTxid() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
  }

  /// 解析 Binding Response，取 XOR-MAPPED-ADDRESS。
  /// magic/txid 不匹配或无 XOR-MAPPED-ADDRESS 时抛 [FormatException]。
  static StunAddress parseBindingResponse(Uint8List response, Uint8List txid) {
    if (response.length < 20) {
      throw const FormatException('stun: response shorter than 20B header');
    }
    final type = (response[0] << 8) | response[1];
    if (type != _typeBindingResponse) {
      throw FormatException(
        'stun: unexpected message type 0x${type.toRadixString(16)}',
      );
    }
    final magic =
        (response[4] << 24) |
        (response[5] << 16) |
        (response[6] << 8) |
        response[7];
    if (magic != magicCookie) {
      throw const FormatException('stun: magic cookie mismatch');
    }
    for (var i = 0; i < 12; i++) {
      if (response[8 + i] != txid[i]) {
        throw const FormatException('stun: txid mismatch');
      }
    }
    final length = (response[2] << 8) | response[3];
    var offset = 20;
    final end = 20 + length;
    while (offset + 4 <= end && offset + 4 <= response.length) {
      final attrType = (response[offset] << 8) | response[offset + 1];
      final attrLen = (response[offset + 2] << 8) | response[offset + 3];
      final valueAt = offset + 4;
      if (attrType == _attrXorMappedAddress && attrLen >= 8) {
        final family = response[valueAt + 1];
        if (family != 0x01) {
          throw FormatException(
            'stun: unsupported address family $family (only IPv4)',
          );
        }
        final xPort =
            ((response[valueAt + 2] << 8) | response[valueAt + 3]) ^
            (magicCookie >> 16);
        var xAddr = 0;
        for (var i = 0; i < 4; i++) {
          xAddr = (xAddr << 8) | response[valueAt + 4 + i];
        }
        xAddr ^= magicCookie;
        return StunAddress(
          host:
              '${(xAddr >> 24) & 0xFF}.${(xAddr >> 16) & 0xFF}.${(xAddr >> 8) & 0xFF}.${xAddr & 0xFF}',
          port: xPort,
        );
      }
      // TLV 按 4B 对齐推进。
      offset = valueAt + attrLen + ((4 - attrLen % 4) % 4);
    }
    throw const FormatException('stun: no XOR-MAPPED-ADDRESS in response');
  }

  /// 在【已有】socket 上发送 Binding 并等反射地址（规格 §1：必须复用打洞 socket）。
  /// 超时抛 [TimeoutException]；收到不相关包则继续等待。
  static Future<StunAddress> discover(
    RawDatagramSocket socket, {
    String host = defaultServer,
    int port = defaultPort,
    Duration timeout = const Duration(seconds: 2),
    Stream<RawSocketEvent>? events,
  }) async {
    final txid = randomTxid();
    final resolved = (await InternetAddress.lookup(host).timeout(timeout))
        .firstWhere((a) => a.type == InternetAddressType.IPv4);
    final completer = Completer<StunAddress>();
    final sub = (events ?? socket).listen((event) {
      if (completer.isCompleted) return;
      final dg = socket.receive();
      if (dg == null) return;
      try {
        completer.complete(parseBindingResponse(dg.data, txid));
      } on FormatException {
        // 不是本次请求的响应（不应发生，保守忽略继续等）。
      }
    });
    // UDP may drop individual packets. Retry the same binding transaction on
    // the same socket so a single lost request does not disable direct transfer.
    Timer? retry;
    try {
      final request = buildBindingRequest(txid);
      socket.send(request, resolved, port);
      retry = Timer.periodic(const Duration(milliseconds: 400), (_) {
        if (!completer.isCompleted) socket.send(request, resolved, port);
      });
      return await completer.future.timeout(timeout);
    } finally {
      retry?.cancel();
      await sub.cancel();
    }
  }
}
