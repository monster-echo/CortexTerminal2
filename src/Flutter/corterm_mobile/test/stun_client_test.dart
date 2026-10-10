import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/features/files/p2p/stun_client.dart';

void main() {
  // 固定 txid：00..0B。
  final txid = Uint8List.fromList(List.generate(12, (i) => i));

  test('Binding Request 固定字节（RFC 5389 §6）', () {
    expect(
      StunClient.buildBindingRequest(txid),
      Uint8List.fromList([
        0x00, 0x01, // type = Binding Request
        0x00, 0x00, // message length
        0x21, 0x12, 0xA4, 0x42, // magic cookie
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, // txid
      ]),
    );
  });

  test('解析 XOR-MAPPED-ADDRESS（固定响应字节）', () {
    // port 54321 (0xD431) ^ 0x2112 = 0xF523；192.0.2.1 ^ cookie = E1 12 A6 43。
    final response = Uint8List.fromList([
      0x01, 0x01, // Binding Response
      0x00, 0x0C, // length 12
      0x21, 0x12, 0xA4, 0x42,
      ...txid,
      0x00, 0x20, // XOR-MAPPED-ADDRESS
      0x00, 0x08,
      0x00, 0x01, // IPv4
      0xF5, 0x23, // xport
      0xE1, 0x12, 0xA6, 0x43, // xaddr
    ]);
    final addr = StunClient.parseBindingResponse(response, txid);
    expect(addr.host, '192.0.2.1');
    expect(addr.port, 54321);
    expect(addr.toString(), '192.0.2.1:54321');
  });

  test('txid 不匹配 / magic 错 / 非 IPv4 抛 FormatException', () {
    final good = Uint8List.fromList([
      0x01, 0x01, 0x00, 0x0C, 0x21, 0x12, 0xA4, 0x42, ...txid,
      0x00, 0x20, 0x00, 0x08, 0x00, 0x01, 0xF5, 0x23, 0xE1, 0x12, 0xA6, 0x43,
    ]);
    expect(
      () => StunClient.parseBindingResponse(good, Uint8List.fromList(List.filled(12, 0xFF))),
      throwsFormatException,
    );

    final badMagic = Uint8List.fromList(good)..[5] = 0x00;
    expect(() => StunClient.parseBindingResponse(badMagic, txid), throwsFormatException);

    final short = Uint8List.fromList([0x01, 0x01]);
    expect(() => StunClient.parseBindingResponse(short, txid), throwsFormatException);

    final badType = Uint8List.fromList(good)..[0] = 0x03;
    expect(() => StunClient.parseBindingResponse(badType, txid), throwsFormatException);
  });

  test('Attribute TLV 跳过未知属性（4B 对齐）', () {
    final response = Uint8List.fromList([
      0x01, 0x01, 0x00, 0x14, 0x21, 0x12, 0xA4, 0x42, ...txid,
      0x00, 0x80, 0x00, 0x03, 0x61, 0x62, 0x63, 0x00, // 未知属性 len 3（pad 到 4）
      0x00, 0x20, 0x00, 0x08, 0x00, 0x01, 0xF5, 0x23, 0xE1, 0x12, 0xA6, 0x43,
    ]);
    final addr = StunClient.parseBindingResponse(response, txid);
    expect(addr.host, '192.0.2.1');
    expect(addr.port, 54321);
  });

  test('buildBindingRequest 拒绝非 12B txid', () {
    expect(() => StunClient.buildBindingRequest(Uint8List(11)), throwsArgumentError);
  });
}
