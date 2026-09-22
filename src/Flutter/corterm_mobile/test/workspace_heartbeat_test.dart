import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:corterm_mobile/core/ws/ws_frames.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/workspace/workspace_controller.dart';
import 'package:corterm_mobile/features/workspace/workspace_state.dart';

/// 假 socket：不连网，只转发注入的帧；记录发送的探测与 forceClose。
class FakeSocket implements TerminalSocket {
  FakeSocket(this.sessionId);

  @override
  final String sessionId;

  final _frames = StreamController<ServerFrame>.broadcast();
  final sentProbes = <String>[];
  bool forceClosed = false;

  void emit(ServerFrame frame) => _frames.add(frame);

  /// 模拟服务端关闭连接（不发我方 close 标记）。
  void closeByServer() {
    if (!_frames.isClosed) _frames.close();
  }

  @override
  Stream<ServerFrame> get frames => _frames.stream;

  @override
  bool get detachedByUs => false;

  @override
  bool get sessionNotFound => false;

  @override
  bool get closedByUs => forceClosed;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void input(String data) {}

  @override
  void resize({required int columns, required int rows}) {}

  @override
  void latencyProbe(String probeId, int clientTime) => sentProbes.add(probeId);

  @override
  void ping(int timestamp) {}

  @override
  Future<void> detach() async {}

  @override
  void close() {}

  @override
  void forceClose() {
    forceClosed = true;
    // 对齐真实 TerminalSocket.forceClose：关闭帧流，让消费方 onDone 做清理。
    if (!_frames.isClosed) _frames.close();
  }
}

/// 假仓库：workspace 控制器只用到 rememberCurrent。
class FakeRepo implements SessionRepository {
  @override
  Future<void> rememberCurrent(String? sessionId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 测试用快照存储：内存 Map 实现（不依赖 SharedPreferences 异步初始化）。
class _FakeSnapshotStore implements TerminalSnapshotStore {
  final _store = <String, String>{};
  final _streams = <String, String>{};
  final _seqs = <String, int>{};

  @override
  String? terminalSnapshot(String key) => _store[key];

  @override
  Future<void> setTerminalSnapshot(String key, String text) async {
    _store[key] = text;
  }

  @override
  String? terminalStreamCache(String key) => _streams[key];

  @override
  Future<void> setTerminalStreamCache(String key, String text) async {
    _streams[key] = text;
  }

  @override
  int terminalSeq(String key) => _seqs[key] ?? 0;

  @override
  Future<void> setTerminalSeq(String key, int seq) async {
    _seqs[key] = seq;
  }
}

AppPreferences testPrefs() {
  SharedPreferences.setMockInitialValues({});
  late AppPreferences prefs;
  SharedPreferences.getInstance().then((p) => prefs = AppPreferences(p));
  return prefs;
}

/// 走完 attaching → replaying → live 全流程（走真实 _handleFrame 逻辑）。
/// broadcast 流异步派发，调用方随后需 flushMicrotasks。
void _goLive(FakeSocket socket) {
  socket.emit(const ReplayingFrame());
  socket.emit(ReplayFrame(bytes: [0x68, 0x69], stream: 'stdout')); // "hi"
  socket.emit(const ReplayCompletedFrame());
  socket.emit(const LiveFrame());
}

void main() {
  test('attach 成功后进入 live，静默超时触发 forceClose + 自动重连', () {
    fakeAsync((async) {
      final created = <FakeSocket>[];
      final controller = WorkspaceController(FakeRepo(), ({required sessionId, sinceSeq = 0}) async {
        final s = FakeSocket(sessionId);
        created.add(s);
        return s;
      }, _FakeSnapshotStore());
      addTearDown(controller.dispose);

      controller.open('s1');
      async.elapse(const Duration(milliseconds: 10));
      _goLive(created[0]);
      async.flushMicrotasks();
      expect(controller.state.entries['s1']!.connState, TerminalConnState.live);
      // live 时已立即探测一次
      expect(created[0].sentProbes, contains('p0'));

      // 静默：10s/20s/30s 周期补发探测，40s 处（>30s 无服务端帧）判死，
      // 1s 退避后（41s，在 45s 窗口内）已用新 socket 发起重连。
      async.elapse(const Duration(seconds: 45));
      expect(created[0].forceClosed, isTrue);
      expect(created.length, 2);
      expect(controller.state.entries['s1']!.connState, TerminalConnState.connecting);
      expect(created[1].forceClosed, isFalse);
    });
  });

  test('有服务端帧活动时不判死', () {
    fakeAsync((async) {
      final created = <FakeSocket>[];
      final controller = WorkspaceController(FakeRepo(), ({required sessionId, sinceSeq = 0}) async {
        final s = FakeSocket(sessionId);
        created.add(s);
        return s;
      }, _FakeSnapshotStore());
      addTearDown(controller.dispose);

      controller.open('s1');
      async.elapse(const Duration(milliseconds: 10));
      _goLive(created[0]);
      async.flushMicrotasks();

      // 每个 10s 周期回一个 pong（touch 活动时间戳），持续 70s 不判死。
      for (var i = 0; i < 7; i++) {
        async.elapse(const Duration(seconds: 10));
        created[0].emit(PongFrame(timestamp: 0));
        async.flushMicrotasks();
      }
      expect(created[0].forceClosed, isFalse);
      expect(controller.state.entries['s1']!.connState, TerminalConnState.live);
    });
  });

  test('displaced 帧置终态错误，且不自动重连', () {
    fakeAsync((async) {
      final created = <FakeSocket>[];
      final controller = WorkspaceController(FakeRepo(), ({required sessionId, sinceSeq = 0}) async {
        final s = FakeSocket(sessionId);
        created.add(s);
        return s;
      }, _FakeSnapshotStore());
      addTearDown(controller.dispose);

      controller.open('s1');
      async.elapse(const Duration(milliseconds: 10));
      _goLive(created[0]);
      async.flushMicrotasks();

      created[0].emit(const DisplacedFrame(reason: 'superseded'));
      async.flushMicrotasks();
      expect(controller.state.entries['s1']!.connState, TerminalConnState.error);
      expect(controller.state.entries['s1']!.errorMessage, 'displaced');
      // 服务端随后关闭连接：终态不自动重连（重连会与另一端互踢）。
      created[0].closeByServer();
      async.elapse(const Duration(seconds: 5));
      expect(created.length, 1);
      expect(controller.state.entries['s1']!.connState, TerminalConnState.error);
    });
  });

  test('退后台断开所有活动连接，回前台立即重连', () {
    fakeAsync((async) {
      final created = <FakeSocket>[];
      final controller = WorkspaceController(FakeRepo(), ({required sessionId, sinceSeq = 0}) async {
        final s = FakeSocket(sessionId);
        created.add(s);
        return s;
      }, _FakeSnapshotStore());
      addTearDown(controller.dispose);

      controller.open('s1');
      async.elapse(const Duration(milliseconds: 10));
      _goLive(created[0]);
      async.flushMicrotasks();
      expect(controller.state.entries['s1']!.connState, TerminalConnState.live);

      controller.enterBackground();
      expect(created[0].forceClosed, isTrue);
      expect(controller.state.entries['s1']!.connState, TerminalConnState.reconnecting);

      // 回前台：重连走 backoff[0]（1s），而非累积退避。
      controller.reattachAll();
      async.elapse(const Duration(seconds: 2));
      expect(created.length, 2);
    });
  });
}

