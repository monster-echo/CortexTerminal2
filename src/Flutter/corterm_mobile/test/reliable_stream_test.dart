import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:corterm_mobile/features/files/p2p/reliable_stream.dart';

/// 环回：A.send → B.handleFrame；B.send → A.handleFrame。
class Loop {
  late ReliableStream a;
  late ReliableStream b;
  final aLost = <int>{}; // A→B 方向按【第几次 DATA 发送】丢弃（模拟丢包）。
  var aSendCount = 0;

  Loop() {
    a = ReliableStream(send: (frame) {
      final parsed = P2pFrame.parse(frame);
      if (parsed.type == frameTypeData) {
        if (aLost.contains(aSendCount)) {
          aSendCount++;
          return; // 丢弃。
        }
        aSendCount++;
      }
      b.handleFrame(frame);
    });
    b = ReliableStream(send: a.handleFrame);
  }
}

void main() {
  test('DATA/ACK 帧编解码往返', () {
    final data = P2pFrame.parse(P2pFrame.encodeData(7, [1, 2, 3]));
    expect(data.type, frameTypeData);
    expect(data.seq, 7);
    expect(data.payload, [1, 2, 3]);

    final ack = P2pFrame.parse(P2pFrame.encodeAck(9, [12, 15, 20, 22]));
    expect(ack.type, frameTypeAck);
    expect(ack.cumulativeAck, 9);
    expect(ack.missingRuns, [12, 15, 20, 22]);

    final fin = P2pFrame.parse(P2pFrame.encodeFin(3));
    expect(fin.type, frameTypeFin);
    expect(fin.seq, 3);
  });

  test('非法帧抛 FormatException', () {
    expect(() => P2pFrame.parse(Uint8List.fromList([0x09, 0, 0, 0, 0, 0, 0])), throwsFormatException);
    // 声明 4B payload 但被截断。
    expect(() => P2pFrame.parse(Uint8List.fromList([0x00, 0, 0, 0, 0, 0, 4])), throwsFormatException);
  });

  test('乱序重组：seq1 先到、seq0 后到，输出按序；ACK 带 SACK 缺失区间', () async {
    final acks = <ParsedFrame>[];
    final recv = ReliableStream(send: (frame) {
      final f = P2pFrame.parse(frame);
      if (f.type == frameTypeAck) acks.add(f);
    });
    recv.handleFrame(P2pFrame.encodeData(1, utf8.encode('B')));
    expect(acks.last.cumulativeAck, 0, reason: 'seq0 缺口前 cum 不推进');
    expect(acks.last.missingRuns, [0, 1], reason: 'closed-run 缺失区间 [0,1)');
    recv.handleFrame(P2pFrame.encodeData(0, utf8.encode('A')));
    expect(acks.last.cumulativeAck, 2);
    final bytes = await recv.bytes.take(2).toList();
    expect(utf8.decode(bytes), 'AB');
  });

  test('环回上传：分块写入 + FIN EOF', () async {
    final loop = Loop();
    final payload = List.generate(3000, (i) => i % 256);
    loop.a.write(payload);
    loop.a.closeWrite();
    final got = await loop.b.readAll();
    expect(got, payload);
    // A 的读侧也能看到 B 的 FIN EOF（closeWrite 双向独立）。
    loop.b.closeWrite();
    await expectLater(loop.a.bytes, emitsDone);
  });

  test('模拟丢包：RTO 300ms 后重传补齐（fake_async）', () {
    fakeAsync((async) {
      final loop = Loop();
      loop.aLost.add(0); // 丢第一个 DATA 包的首次发送。
      Object? result;
      loop.b.readAll().then((v) => result = v);
      loop.a.write(utf8.encode('XY'));
      loop.a.closeWrite();
      async.elapse(const Duration(milliseconds: 700));
      expect(result, isNotNull, reason: 'RTO 重传后应补齐并 EOF');
      expect(utf8.decode(result! as List<int>), 'XY');
    });
  });

  test('3 个冗余 ACK 触发快速重传（fake_async）', () {
    fakeAsync((async) {
      var seq0Sends = 0;
      final sender = ReliableStream(send: (frame) {
        final f = P2pFrame.parse(frame);
        if (f.type == frameTypeData && f.seq == 0) seq0Sends++;
      });
      sender.write(utf8.encode('AB'));
      expect(seq0Sends, 1);
      // 模拟对端 seq1 丢失：首个 ACK(0) 是对 seq0 之前数据的确认，随后 3 个为冗余 ACK。
      sender.handleFrame(P2pFrame.encodeAck(0, const []));
      sender.handleFrame(P2pFrame.encodeAck(0, const []));
      sender.handleFrame(P2pFrame.encodeAck(0, const []));
      sender.handleFrame(P2pFrame.encodeAck(0, const []));
      async.elapse(const Duration(milliseconds: 10));
      expect(seq0Sends, 2, reason: '冗余 ACK ≥3 应立即快重 seq0，不等 RTO');
      // 同一 cum 只快重一次。
      sender.handleFrame(P2pFrame.encodeAck(0, const []));
      async.elapse(const Duration(milliseconds: 10));
      expect(seq0Sends, 2);
      sender.dispose();
    });
  });

  test('窗口 32：积压包在 ACK 推进后发出', () {
    final sent = <int>[];
    final sender = ReliableStream(send: (frame) {
      final f = P2pFrame.parse(frame);
      if (f.type == frameTypeData) sent.add(f.seq);
    });
    sender.write(List.filled(40 * 1150, 7)); // 40 包。
    expect(sent.length, 32, reason: '窗口 32 包');
    sender.handleFrame(P2pFrame.encodeAck(32, const []));
    expect(sent.length, 40, reason: 'ACK 推进后 backlog 下水');
    sender.dispose();
  });

  test('RST 中止读侧', () {
    final recv = ReliableStream(send: (_) {});
    recv.handleFrame(P2pFrame.encodeRst(0));
    expect(
      recv.bytes,
      emitsInOrder([emitsError(isA<P2pStreamReset>()), emitsDone]),
    );
  });

  test('ACK 全部确认后停止 FIN 重发', () {
    fakeAsync((async) {
      var finSends = 0;
      final sender = ReliableStream(send: (frame) {
        if (P2pFrame.parse(frame).type == frameTypeFin) finSends++;
      });
      sender.closeWrite();
      expect(finSends, 1);
      async.elapse(const Duration(milliseconds: 950));
      expect(finSends, greaterThan(1), reason: 'FIN 未确认前周期重发');
      sender.handleFrame(P2pFrame.encodeAck(0, const [])); // cum ≥ finSeq(0)
      final before = finSends;
      async.elapse(const Duration(milliseconds: 950));
      expect(finSends, before);
    });
  });
}
