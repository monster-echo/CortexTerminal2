import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:corterm_mobile/core/ws/ws_frames.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';

/// 假 socket：不连网。
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

class FakeSnapshotStore implements TerminalSnapshotStore {
  final store = <String, String>{};
  final streams = <String, String>{};
  final seqs = <String, int>{};

  @override
  String? terminalSnapshot(String key) => store[key];
  @override
  Future<void> setTerminalSnapshot(String key, String text) async {
    store[key] = text;
  }

  @override
  String? terminalStreamCache(String key) => streams[key];

  @override
  int terminalSeq(String key) => seqs[key] ?? 0;

  @override
  Future<void> setTerminalSeq(String key, int seq) async {
    seqs[key] = seq;
  }
  @override
  Future<void> setTerminalStreamCache(String key, String text) async {
    streams[key] = text;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());
  String? clipboardText;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map<String, dynamic>)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
  });

  Future<SessionController> makeController(
      FakeSnapshotStore snapshotStore) async {
    final controller = SessionController(
      FakeRepo(),
      ({required sessionId, sinceSeq = 0}) async => FakeSocket(sessionId),
      snapshotStore,
    );
    return controller;
  }

  test('OSC 52：远端写剪贴板 → 本地剪贴板 + clipboard 通知', () async {
    final store = FakeSnapshotStore();
    final controller = await makeController(store);
    await controller.open('s1');

    // 'hello from remote' 的 base64。
    controller.state.entries['s1']!
        .terminal
        .write('\x1b]52;c;aGVsbG8gZnJvbSByZW1vdGU=\x07');

    expect(clipboardText, 'hello from remote');
    expect(controller.state.oscNotice?.kind, OscNoticeKind.clipboard);
    expect(controller.state.oscNotice?.message, 'hello from remote');
  });

  test('OSC 52：非法 base64 被忽略，不写剪贴板', () async {
    final controller = await makeController(FakeSnapshotStore());
    await controller.open('s1');

    controller.state.entries['s1']!.terminal.write('\x1b]52;c;@@@not-base64@@@\x07');

    expect(clipboardText, isNull);
    expect(controller.state.oscNotice, isNull);
  });

  test('OSC 7：file:// 目录上报 → remoteCwd 记录（host 剥离）', () async {
    final controller = await makeController(FakeSnapshotStore());
    await controller.open('s1');

    controller.state.entries['s1']!
        .terminal
        .write('\x1b]7;file://myserver/home/user/project\x07');

    expect(
      controller.state.entries['s1']!.remoteCwd,
      '/home/user/project',
    );
  });

  test('OSC 9：通知消息进入状态，剪贴板不受影响', () async {
    final controller = await makeController(FakeSnapshotStore());
    await controller.open('s1');

    controller.state.entries['s1']!.terminal.write('\x1b]9;deploy done\x07');

    expect(clipboardText, isNull);
    expect(controller.state.oscNotice?.kind, OscNoticeKind.notify);
    expect(controller.state.oscNotice?.message, 'deploy done');
  });

  test('OSC 9 Windows Terminal 形态：首段为序列号时剥掉', () async {
    final controller = await makeController(FakeSnapshotStore());
    await controller.open('s1');

    controller.state.entries['s1']!.terminal.write('\x1b]9;1;build finished\x07');

    expect(controller.state.oscNotice?.message, 'build finished');
  });

  test('clearOscNotice：清空后监听方不再收到', () async {
    final controller = await makeController(FakeSnapshotStore());
    await controller.open('s1');

    controller.state.entries['s1']!.terminal.write('\x1b]9;notify me\x07');
    expect(controller.state.oscNotice, isNotNull);

    controller.clearOscNotice();
    expect(controller.state.oscNotice, isNull);
  });

  test('输出流缓存：重放/输出写入 3s 后落盘（TerminalCache 对等）', () {
    fakeAsync((async) {
      final store = FakeSnapshotStore();
      final created = <FakeSocket>[];
      final controller = SessionController(
        FakeRepo(),
        ({required sessionId, sinceSeq = 0}) async {
          final s = FakeSocket(sessionId);
          created.add(s);
          return s;
        },
        store,
      );
      addTearDown(controller.dispose);

      controller.open('s1');
      async.elapse(const Duration(milliseconds: 10));

      // 走真实帧路径：ReplayingFrame 重建 → Replay 携带输出 → completed 落盘调度。
      created[0].emit(const ReplayingFrame());
      created[0]
          .emit(ReplayFrame(bytes: utf8.encode('hello scrollback'), stream: 'stdout'));
      created[0].emit(const ReplayCompletedFrame());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4)); // 3s 防抖

      expect(store.streams['s1'], contains('hello scrollback'));
    });
  });
}

