/// P2P 会话密钥与数据报加密（规格 §3.1/§3.2）。
///
/// - `key = HKDF-SHA256(ikm = RelayToken 原文字节, salt = transferId UTF-8,
///   info = "corterm-p2p-v1", L = 32)`（RFC 5869，基于 package:crypto 的 HMAC 手写）。
/// - AES-256-GCM（package:cryptography，纯 Dart、AOT 安全）。
/// - 包格式：`[1B version=0x01][12B nonce][ciphertext+tag16B]`，
///   nonce = 4B 随机前缀（每连接一次）+ 8B 大端计数器（每方向独立递增），AAD = 空。
/// - 解密失败（tag 不过）→ [P2pCipher.open] 返回 null，调用方按规格丢弃该包。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';

/// HKDF-SHA256（RFC 5869）：Extract(salt, ikm) → Expand(prk, info, L)。
Uint8List hkdfSha256({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  int length = 32,
}) {
  // Extract：PRK = HMAC-SHA256(salt, ikm)。
  final prk = c.Hmac(c.sha256, salt).convert(ikm).bytes;
  // Expand：T(0)=空；T(i) = HMAC(PRK, T(i-1) | info | i)。
  final okm = BytesBuilder();
  var t = <int>[];
  var counter = 1;
  while (okm.length < length) {
    final mac = c.Hmac(c.sha256, prk);
    final input = BytesBuilder()..add(t)..add(info)..addByte(counter);
    t = mac.convert(input.toBytes()).bytes;
    okm.add(t);
    counter++;
  }
  return Uint8List.fromList(okm.toBytes().sublist(0, length));
}

class P2pCipher {
  P2pCipher._(Uint8List key)
      : _algorithm = AesGcm.with256bits(),
        _key = SecretKeyData(key) {
    final rng = Random.secure();
    _noncePrefix = Uint8List.fromList(List.generate(4, (_) => rng.nextInt(256)));
  }

  /// 从 RelayToken 原文 + transferId 派生密钥（§3.1）。
  factory P2pCipher.fromToken({required String token, required String transferId}) {
    final key = hkdfSha256(
      ikm: utf8.encode(token),
      salt: utf8.encode(transferId),
      info: utf8.encode(info),
    );
    return P2pCipher._(key);
  }

  /// 规格 §3.1 固定 info。
  static const info = 'corterm-p2p-v1';

  static const versionByte = 0x01;
  static const nonceLength = 12;
  static const tagLength = 16;

  final AesGcm _algorithm;
  final SecretKeyData _key;
  late final Uint8List _noncePrefix;
  int _counter = 0;

  Future<void> _sealing = Future<void>.value();

  /// 加密一帧（§3.3 明文 payload）为 UDP 包。同一连接内按调用顺序上 counter，
  /// 经 [_sealing] 链保证加密后的包按 counter 顺序发出（乱序到达由可靠层处理）。
  Future<Uint8List> seal(List<int> plaintextFrame) {
    final nonce = _nextNonce();
    final done = _sealing.then((_) async {
      final box = await _algorithm.encrypt(plaintextFrame, secretKey: _key, nonce: nonce);
      return _packet(nonce, box);
    });
    _sealing = done;
    return done;
  }

  Uint8List _nextNonce() {
    final c = _counter++;
    final nonce = Uint8List(nonceLength);
    nonce.setRange(0, 4, _noncePrefix);
    for (var i = 0; i < 8; i++) {
      nonce[11 - i] = (c >> (8 * i)) & 0xFF;
    }
    return nonce;
  }

  Uint8List _packet(Uint8List nonce, SecretBox box) {
    final b = BytesBuilder();
    b.addByte(versionByte);
    b.add(nonce);
    b.add(box.cipherText);
    b.add(box.mac.bytes);
    return b.toBytes();
  }

  /// 解包 + 解密。格式/版本非法或 GCM tag 校验不过 → null（调用方丢弃）。
  Future<Uint8List?> open(Uint8List packet) async {
    if (packet.length < 1 + nonceLength + tagLength) return null;
    if (packet[0] != versionByte) return null;
    final nonce = Uint8List.sublistView(packet, 1, 1 + nonceLength);
    final ct = Uint8List.sublistView(packet, 1 + nonceLength, packet.length - tagLength);
    final mac = Mac(Uint8List.sublistView(packet, packet.length - tagLength));
    try {
      final box = await _algorithm.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: _key);
      return Uint8List.fromList(box);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}
