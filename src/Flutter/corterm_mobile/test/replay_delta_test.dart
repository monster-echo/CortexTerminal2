import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:corterm_mobile/core/ws/ws_frames.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';
import 'package:corterm_mobile/features/session/session_state.dart';

class FakeSocket implements TerminalSocket {
  FakeSocket(this.sessionId);

  @override
  final String sessionId;

  final _frames = StreamController<ServerFrame>.broadcast();

  void emit(ServerFrame frame) => _frames.add(frame);

  @override
  Stream<ServerFrame> get frames => _frames.stream;
  @override
  bool get detachedByUs => false;
  @override
  bool get sessionNotFound => false;
  @override
  bool get closedByUs => false;
  @override
  Future<void> get done => Completer<void>().future;
  @override
  void input(String data) {}
  @override
  void resize({required int columns, required int rows}) {}
  @override
  void latencyProbe(String probeId, int clientTime) {}
  @override
  void ping(int timestamp) {}
  @override
  Future<void> detach() async {}
  @override
  void close() {}
  @override
  void forceClose() {
    if (!_frames.isClosed) _frames.close();
  }
}

class FakeRepo implements SessionRepository {
  @override
  Future<void> rememberCurrent(String? sessionId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeStore implements TerminalSnapshotStore {
  final snapshots = <String, String>{};
  final streams = <String, String>{};
  final seqs = <String, int>{};

  @override
  String? terminalSnapshot(String key) => snapshots[key];
  @override
  Future<void> setTerminalSnapshot(String key, String text) async {
    snapshots[key] = text;
  }

  @override
  String? terminalStreamCache(String key) => streams[key];
  @override
  Future<void> setTerminalStreamCache(String key, String text) async {
    streams[key] = text;
  }

  @override
  int terminalSeq(String key) => seqs[key] ?? 0;
  @override
  Future<void> setTerminalSeq(String key, int seq) async {
    seqs[key] = seq;
  }
}

String _bufferText(Terminal terminal) {
  final buffer = terminal.buffer;
  final sb = StringBuffer();
  for (var i = 0; i < buffer.height; i++) {
    sb.writeln(buffer.lines[i].getText());
  }
  return sb.toString();
}

void main() {
  group('ws_frames 增量帧', () {
    test('replayDelta：payload 解码 + seq 透传', () {
      final frame = WsFrames.parseServerFrame(
        '{"type":"replayDelta","sessionId":"s1","stream":"stdout",'
        '"payload":"${base64Encode(utf8.encode('hi'))}","seq":7}',
      );
      expect(frame, isA<ReplayDeltaFrame>());
      final delta = frame as ReplayDeltaFrame;
      expect(utf8.decode(delta.bytes), 'hi');
      expect(delta.seq, 7);
    });

    test('replayDeltaStarted / replayDeltaCompleted', () {
      expect(WsFrames.parseServerFrame('{"type":"replayDeltaStarted","sessionId":"s1"}'),
          isA<ReplayDeltaStartedFrame>());
      final done = WsFrames.parseServerFrame(
          '{"type":"replayDeltaCompleted","sessionId":"s1","lastSeq":42}');
      expect((done as ReplayDeltaCompletedFrame).lastSeq, 42);
    });

    test('buildUri：since>0 才携带 since 参数', () {
      final base = WsFrames.buildUri(
        gatewayBaseUrl: 'https://gw.example',
        token: 'tok',
        sessionId: 's1',
      );
      expect(base.queryParameters.containsKey('since'), isFalse);

      final withSince = WsFrames.buildUri(
        gatewayBaseUrl: 'https://gw.example',
        token: 'tok',
        sessionId: 's1',
        sinceSeq: 42,
      );
      expect(withSince.queryParameters['since'], '42');
    });
  });

  group('控制器增量重放', () {
    late FakeStore store;
    late FakeSocket socket;
    late SessionController controller;

    setUp(() async {
      store = FakeStore();
      controller = SessionController(
        FakeRepo(),
        ({required sessionId, sinceSeq = 0}) async {
          socket = FakeSocket(sessionId);
          return socket;
        },
        store,
      );
      await controller.open('s1');
      await pumpEventQueue();
    });

    tearDown(() {
      controller.dispose();
    });

    test('全量重放清零游标', () async {
      socket.emit(const ReplayingFrame());
      socket.emit(ReplayFrame(bytes: utf8.encode('before'), stream: 'stdout'));
      socket.emit(const ReplayCompletedFrame());
      await pumpEventQueue();

      expect(store.seqs['s1'], 0);
      expect(_bufferText(controller.state.entries['s1']!.terminal),
          contains('before'));
    });

    test('delta 帧无缝续写：不重置已绘制画面，游标推进并持久化', () async {
      // 先走一遍全量重放，画上 'before'。
      socket.emit(const ReplayingFrame());
      socket.emit(ReplayFrame(bytes: utf8.encode('before'), stream: 'stdout'));
      socket.emit(const ReplayCompletedFrame());
      await pumpEventQueue();

      // 增量重放：不重置 → 'after' 续写在 'before' 之后。
      socket.emit(const ReplayDeltaStartedFrame());
      socket.emit(ReplayDeltaFrame(
        bytes: utf8.encode('after'),
        stream: 'stdout',
        seq: 7,
      ));
      socket.emit(const ReplayDeltaCompletedFrame(lastSeq: 7));
      await pumpEventQueue();

      final text = _bufferText(controller.state.entries['s1']!.terminal);
      expect(text, contains('before'));
      expect(text, contains('after'));
      expect(controller.state.entries['s1']!.connState, TerminalConnState.live);
      expect(store.seqs['s1'], 7);
    });

    test('delta 期间断线重连：游标推进后再次走增量', () async {
      socket.emit(const ReplayDeltaStartedFrame());
      socket.emit(ReplayDeltaFrame(
        bytes: utf8.encode('part1'),
        stream: 'stdout',
        seq: 3,
      ));
      socket.emit(const ReplayDeltaCompletedFrame(lastSeq: 3));
      await pumpEventQueue();

      expect(store.seqs['s1'], 3);
      // 连接被服务端关闭 → 自动重连应带 since=3。
      socket.emit(const LiveFrame());
      await pumpEventQueue();
      expect(store.seqs['s1'], 3);
    });
  });
}
