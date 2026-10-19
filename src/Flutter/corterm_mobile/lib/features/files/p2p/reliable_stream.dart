/// 可靠流（ARQ）— 规格 §3.3：DATA/ACK/FIN/RST 帧、窗口 32、
/// RTO 300ms 指数退避（上限 2s）、3 个冗余 ACK 快速重传、乱序重组、字节流读取。
library;

import 'dart:async';
import 'dart:typed_data';

// ---- 帧常量（§3.3）----

const int frameTypeData = 0x00;
const int frameTypeAck = 0x01;
const int frameTypeFin = 0x02;
const int frameTypeRst = 0x03;

/// MTU 1200 − 包头 13 − GCM 开销。
const int maxDataPayload = 1150;

/// 接收/发送窗口（包）。
const int windowPackets = 32;

/// RTO 基值与上限。
const Duration rtoBase = Duration(milliseconds: 300);
const Duration rtoMax = Duration(seconds: 2);

/// 冗余 ACK 次数阈值（达到即快速重传 cumulativeAck 指向的包）。
const int fastRetransmitDupAcks = 3;

class ParsedFrame {
  const ParsedFrame({
    required this.type,
    required this.seq,
    this.payload = const <int>[],
    this.cumulativeAck = 0,
    this.missingRuns = const <int>[],
  });

  final int type;
  final int seq;

  /// DATA payload（DATA 帧）。
  final List<int> payload;

  /// ACK 帧：cumulativeAck = 对端已连续收到的最高 seq + 1。
  final int cumulativeAck;

  /// ACK 帧：缺失区间 closed-run 平铺 [start0, end0, start1, end1, ...]，
  /// 缺失 = [start, end)（end 不含）。
  final List<int> missingRuns;
}

/// 帧编解码（明文 payload，加密在 [P2pCipher] 层）。
class P2pFrame {
  P2pFrame._();

  static Uint8List encodeData(int seq, List<int> payload) =>
      _withPayload(frameTypeData, seq, payload);

  static Uint8List encodeAck(int cumulativeAck, List<int> missingRuns) =>
      _withPayload(frameTypeAck, 0, [cumulativeAck >> 24 & 0xFF, cumulativeAck >> 16 & 0xFF, cumulativeAck >> 8 & 0xFF, cumulativeAck & 0xFF, ..._runsPayload(missingRuns)]);

  static Uint8List encodeFin(int seq) => _withPayload(frameTypeFin, seq, const []);

  static Uint8List encodeRst(int seq) => _withPayload(frameTypeRst, seq, const []);

  static Uint8List _withPayload(int type, int seq, List<int> payload) {
    if (payload.length > 0xFFFF) throw ArgumentError.value(payload.length, 'payload', 'too long');
    final b = BytesBuilder();
    b.addByte(type);
    b.addByte((seq >> 24) & 0xFF);
    b.addByte((seq >> 16) & 0xFF);
    b.addByte((seq >> 8) & 0xFF);
    b.addByte(seq & 0xFF);
    b.addByte(payload.length >> 8);
    b.addByte(payload.length & 0xFF);
    b.add(payload);
    return b.toBytes();
  }

  static List<int> _runsPayload(List<int> missingRuns) {
    if (missingRuns.length.isOdd) {
      throw ArgumentError.value(missingRuns, 'missingRuns', 'closed-run pairs must be flat');
    }
    final runCount = missingRuns.length ~/ 2;
    final out = <int>[];
    out.add((runCount >> 24) & 0xFF);
    out.add((runCount >> 16) & 0xFF);
    out.add((runCount >> 8) & 0xFF);
    out.add(runCount & 0xFF);
    for (final v in missingRuns) {
      out.addAll([v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF]);
    }
    return out;
  }

  static ParsedFrame parse(Uint8List bytes) {
    if (bytes.length < 7) throw const FormatException('p2p frame: shorter than 7B header');
    final type = bytes[0];
    if (type != frameTypeData && type != frameTypeAck && type != frameTypeFin && type != frameTypeRst) {
      throw FormatException('p2p frame: unknown type 0x${type.toRadixString(16)}');
    }
    final seq = (bytes[1] << 24) | (bytes[2] << 16) | (bytes[3] << 8) | bytes[4];
    final len = (bytes[5] << 8) | bytes[6];
    if (bytes.length < 7 + len) throw const FormatException('p2p frame: truncated payload');
    final payload = Uint8List.sublistView(bytes, 7, 7 + len);
    switch (type) {
      case frameTypeData:
        return ParsedFrame(type: type, seq: seq, payload: payload);
      case frameTypeAck:
        if (len < 8) throw const FormatException('p2p frame: ACK payload too short');
        final cum = (payload[0] << 24) | (payload[1] << 16) | (payload[2] << 8) | payload[3];
        final runCount = (payload[4] << 24) | (payload[5] << 16) | (payload[6] << 8) | payload[7];
        if (len < 8 + runCount * 8) throw const FormatException('p2p frame: ACK runs truncated');
        final runs = <int>[];
        for (var i = 0; i < runCount * 2; i++) {
          final o = 8 + i * 4;
          runs.add((payload[o] << 24) | (payload[o + 1] << 16) | (payload[o + 2] << 8) | payload[o + 3]);
        }
        return ParsedFrame(type: type, seq: seq, cumulativeAck: cum, missingRuns: runs);
      default:
        return ParsedFrame(type: type, seq: seq);
    }
  }
}

/// 可靠流被 RST 中止。
class P2pStreamReset implements Exception {
  const P2pStreamReset();

  @override
  String toString() => 'P2P stream reset by peer';
}

class _Pending {
  _Pending({required this.seq, required this.payload});

  final int seq;
  final Uint8List payload;
  Duration rto = rtoBase;
  Timer? timer;
  int transmissions = 0;

  void cancel() {
    timer?.cancel();
    timer = null;
  }
}

class ReliableStream {
  ReliableStream({required this._send});

  final void Function(Uint8List frame) _send;

  final _output = StreamController<int>();
  final _pending = <int, _Pending>{};
  final _backlog = <_Pending>[];

  int _nextSendSeq = 0;
  bool _writeClosed = false;

  // 冗余 ACK 计数（同一 cumulativeAck 的连续次数）。
  int _lastCumAck = -1;
  int _dupAcks = 0;

  // 接收侧。
  int _expectedSeq = 0;
  final _reorder = <int, Uint8List>{};
  int? _finSeq;
  bool _eof = false;

  Timer? _finTimer;

  /// 上层读取字节流（FIN 后自然 done；RST 抛 [P2pStreamReset]）。
  Stream<int> get bytes => _output.stream;

  /// 读到 EOF 为止的全部字节。
  Future<Uint8List> readAll() async {
    final out = BytesBuilder();
    await for (final b in bytes) {
      out.addByte(b);
    }
    return out.toBytes();
  }

  // ---- 写侧 ----

  /// 写字节（自动切 ≤1150B 的 DATA 包，受 32 包窗口约束）。
  void write(List<int> bytes) {
    if (_writeClosed) throw StateError('reliable stream: write after FIN');
    if (_eof) throw StateError('reliable stream: read side already at EOF');
    for (var offset = 0; offset < bytes.length; offset += maxDataPayload) {
      final end = offset + maxDataPayload > bytes.length ? bytes.length : offset + maxDataPayload;
      _enqueue(Uint8List.fromList(bytes.sublist(offset, end)));
    }
  }

  /// 本端写完：发 FIN（seq = 下一个 DATA 序号）。对端读侧随后 EOF。
  void closeWrite() {
    if (_writeClosed) return;
    _writeClosed = true;
    final finSeq = _nextSendSeq;
    _send(P2pFrame.encodeFin(finSeq));
    _finTimer = Timer.periodic(rtoBase, (_) => _send(P2pFrame.encodeFin(finSeq)));
  }

  void _enqueue(Uint8List chunk) {
    final p = _Pending(seq: _nextSendSeq++, payload: chunk);
    if (_pending.length >= windowPackets) {
      _backlog.add(p);
    } else {
      _pending[p.seq] = p;
      _transmit(p);
    }
  }

  void _transmit(_Pending p) {
    p.transmissions++;
    _send(P2pFrame.encodeData(p.seq, p.payload));
    p.timer ??= Timer(p.rto, () => _onRto(p));
  }

  void _onRto(_Pending p) {
    p.timer = null;
    p.rto = p.rto * 2 > rtoMax ? rtoMax : p.rto * 2;
    _transmit(p);
  }

  // ---- 收侧入口（解密后的明文帧）----

  void handleFrame(Uint8List frame) {
    final f = P2pFrame.parse(frame);
    switch (f.type) {
      case frameTypeAck:
        _onAck(f);
      case frameTypeData:
        _onData(f);
      case frameTypeFin:
        _onFin(f);
      case frameTypeRst:
        abort(const P2pStreamReset());
    }
  }

  void _onData(ParsedFrame f) {
    if (_eof) return;
    if (f.seq < _expectedSeq || _reorder.containsKey(f.seq)) {
      // 重复包：重发 ACK（乱序检测靠 ACK 推进）。
      _sendAck();
      return;
    }
    if (f.seq == _expectedSeq) {
      _deliver(f.payload);
      while (_reorder.containsKey(_expectedSeq)) {
        _deliver(_reorder.remove(_expectedSeq)!);
      }
      if (_finSeq != null && _expectedSeq == _finSeq) {
        _finishEof();
        return;
      }
    } else {
      _reorder[f.seq] = Uint8List.fromList(f.payload);
    }
    _sendAck();
  }

  void _onFin(ParsedFrame f) {
    if (_eof) return;
    _finSeq = f.seq;
    if (f.seq == _expectedSeq) {
      _finishEof();
    } else {
      // 前面还有缺口：回 ACK（带缺失区间），等补齐后 EOF。
      _sendAck();
    }
  }

  void _deliver(List<int> payload) {
    for (final b in payload) {
      _output.add(b);
    }
    _expectedSeq++;
  }

  void _finishEof() {
    _eof = true;
    _finTimer?.cancel();
    _output.close();
  }

  /// 缺失区间 closed-run 平铺：[_expectedSeq, maxSeq) 内未被缓存覆盖的区间。
  List<int> _missingRuns() {
    if (_reorder.isEmpty) return const [];
    final buffered = _reorder.keys.toList()..sort();
    final runs = <int>[];
    var gapStart = _expectedSeq;
    for (final seq in buffered) {
      if (seq > gapStart) {
        runs..add(gapStart)..add(seq);
      }
      gapStart = seq + 1;
    }
    return runs;
  }

  void _sendAck() {
    _send(P2pFrame.encodeAck(_expectedSeq, _missingRuns()));
  }

  // ---- ACK 处理（发送侧）----

  void _onAck(ParsedFrame f) {
    final cum = f.cumulativeAck;
    _pending.removeWhere((seq, p) {
      if (seq < cum) {
        p.cancel();
        return true;
      }
      return false;
    });
    while (_pending.length < windowPackets && _backlog.isNotEmpty) {
      final p = _backlog.removeAt(0);
      _pending[p.seq] = p;
      _transmit(p);
    }
    if (cum >= _nextSendSeq) {
      // 全部确认（含 FIN seq）：停止 FIN 重发。
      _finTimer?.cancel();
      _finTimer = null;
    }
    if (cum == _lastCumAck) {
      _dupAcks++;
    } else {
      _lastCumAck = cum;
      _dupAcks = 0;
    }
    // 3 个冗余 ACK：立即重传 cum 指向的包（一次），RTO 计时保持。
    if (_dupAcks >= fastRetransmitDupAcks) {
      final lost = _pending[cum];
      if (lost != null) {
        _send(P2pFrame.encodeData(lost.seq, lost.payload));
        _dupAcks = -(1 << 30); // 同一 cum 只快重一次，等 cum 推进后复位。
      }
    }
  }

  /// 异常中止：发 RST 并让读侧报错。
  void abort([Object? error]) {
    _finTimer?.cancel();
    _send(P2pFrame.encodeRst(_nextSendSeq));
    _output.addError(error ?? const P2pStreamReset());
    _output.close();
    _eof = true;
  }

  /// 释放本地资源（不发任何帧）。
  void dispose() {
    for (final p in _pending.values) {
      p.cancel();
    }
    _finTimer?.cancel();
    if (!_output.isClosed) _output.close();
  }
}
