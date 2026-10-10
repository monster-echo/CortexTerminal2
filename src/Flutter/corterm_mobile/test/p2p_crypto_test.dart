import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/features/files/p2p/p2p_crypto.dart';

void main() {
  test('HKDF-SHA256 RFC 5869 Test Case 1 固定向量', () {
    final okm = hkdfSha256(
      ikm: List.filled(22, 0x0B),
      salt: List.generate(13, (i) => i),
      info: List.generate(10, (i) => 0xF0 + i),
      length: 42,
    );
    expect(
      okm.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865',
    );
  });

  test('HKDF-SHA256 RFC 5869 Test Case 3（空 salt/info）', () {
    final okm = hkdfSha256(ikm: List.filled(22, 0x0B), salt: const [], info: const [], length: 42);
    expect(
      okm.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, 64),
      '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d',
    );
  });

  test('AES-256-GCM 包往返（§3.2 格式）', () async {
    final a = P2pCipher.fromToken(token: 'relay-token', transferId: 'tid-1');
    final b = P2pCipher.fromToken(token: 'relay-token', transferId: 'tid-1');
    final frame = utf8.encode('hello p2p');
    final packet = await a.seal(frame);
    // 包格式：1B version + 12B nonce + 密文 + 16B tag。
    expect(packet[0], 0x01);
    expect(packet.length, 1 + 12 + frame.length + 16);
    final plain = await b.open(packet);
    expect(plain, frame);
  });

  test('nonce 计数器每包递增（大端 8B）', () async {
    final a = P2pCipher.fromToken(token: 't', transferId: 'tid');
    final p1 = await a.seal([1]);
    final p2 = await a.seal([2]);
    // nonce 位于 packet[1..13)，计数器低字节在 packet[12]。
    expect(p1.sublist(1, 13), isNot(p2.sublist(1, 13)));
    // 计数器 0 → 1：低字节 +1（nonce 位于 packet[1..13)）。
    expect(p2[12], p1[12] + 1);
  });

  test('两方向（两个 cipher 实例）nonce 前缀独立', () async {
    final a = P2pCipher.fromToken(token: 't', transferId: 'tid');
    final b = P2pCipher.fromToken(token: 't', transferId: 'tid');
    final pa = await a.seal([1]);
    final pb = await b.seal([1]);
    expect(pa.sublist(1, 5), isNot(pb.sublist(1, 5)));
  });

  test('密钥派生：token 或 transferId 不同 → 解不开', () async {
    final a = P2pCipher.fromToken(token: 't1', transferId: 'tid');
    final wrong = P2pCipher.fromToken(token: 't2', transferId: 'tid');
    final packet = await a.seal(utf8.encode('secret'));
    expect(await wrong.open(packet), isNull);
    final wrongTid = P2pCipher.fromToken(token: 't1', transferId: 'other');
    expect(await wrongTid.open(packet), isNull);
  });

  test('tag 校验失败 / 格式非法 → null（丢弃）', () async {
    final a = P2pCipher.fromToken(token: 't', transferId: 'tid');
    final packet = await a.seal(utf8.encode('secret'));
    final tampered = Uint8List.fromList(packet)..[packet.length - 1] ^= 0xFF;
    expect(await a.open(tampered), isNull);

    expect(await a.open(Uint8List.fromList([0x01, 0, 0])), isNull); // 太短
    final badVersion = Uint8List.fromList(packet)..[0] = 0x02;
    expect(await a.open(badVersion), isNull);
  });
}
