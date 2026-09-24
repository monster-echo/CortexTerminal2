import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corterm_mobile/core/api/api_client.dart';
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';
import 'package:corterm_mobile/features/session/session_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late HttpServer server;
  final received = <String>[];

  setUp(() async {
    received.clear();
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.add(jsonEncode({'type': 'live'}));
      ws.listen((data) => received.add(data as String));
    });
  });

  tearDown(() => server.close(force: true));

  Future<SessionController> makeController() async {
    final prefs = AppPreferences(await SharedPreferences.getInstance());
    final repo = SessionRepository(
      ApiClient(
        baseUrl: 'http://127.0.0.1:1',
        tokenStore: TokenStore(const FlutterSecureStorage()),
      ),
      prefs,
    );
    TerminalSocketFactory factory = ({required sessionId, sinceSeq = 0}) {
      return TerminalSocket.connect(
        gatewayBaseUrl: 'http://127.0.0.1:${server.port}',
        token: 'test-token',
        sessionId: sessionId,
        sinceSeq: sinceSeq,
      );
    };
    return SessionController(repo, factory, prefs);
  }

  Future<void> waitUntilLive(SessionController c, String sessionId) async {
    for (var i = 0; i < 100; i++) {
      final e = c.state.entries[sessionId];
      if (e != null && e.connState == TerminalConnState.live) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('session never went live: ${c.state.entries[sessionId]?.connState}');
  }

  List<Map<String, dynamic>> inputFrames() => received
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((f) => f['type'] == 'input')
      .toList();

  test('sticky CTRL latches: consecutive chars all send as control chars',
      () async {
    final c = await makeController();
    await c.open('s1');
    await waitUntilLive(c, 's1');

    c.setCtrlArmed(true);
    expect(c.state.ctrlArmed, isTrue);

    // 软键盘 IME 输入路径：onInsert → terminal.textInput('c') → onOutput
    final term = c.state.entries['s1']!.terminal;
    term.textInput('c');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    term.textInput('c');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // latch：输入不自动取消，连续两个 c 都是 ^C。
    expect(c.state.ctrlArmed, isTrue);
    final frames = inputFrames();
    expect(frames, hasLength(2));
    for (final f in frames) {
      final payload = utf8.decode(base64Decode(f['payload'] as String));
      expect(payload.codeUnits, [0x03],
          reason: 'sticky CTRL + c must send ETX');
    }

    // 手动再点 CTRL 才取消；取消后恢复普通字符。
    c.setCtrlArmed(false);
    term.textInput('c');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.state.ctrlArmed, isFalse);
    final last =
        utf8.decode(base64Decode(inputFrames().last['payload'] as String));
    expect(last, 'c');
  });

  test('sticky ALT: next char is sent with ESC prefix', () async {
    final c = await makeController();
    await c.open('s1');
    await waitUntilLive(c, 's1');

    c.setAltArmed(true);
    c.state.entries['s1']!.terminal.textInput('b');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // latch：吸合保持，直到手动取消。
    expect(c.state.altArmed, isTrue);
    final frames = inputFrames();
    expect(frames, hasLength(1));
    final payload =
        utf8.decode(base64Decode(frames.first['payload'] as String));
    expect(payload.codeUnits, [0x1b, 0x62]);
  });

  test('plain input passes through unchanged', () async {
    final c = await makeController();
    await c.open('s1');
    await waitUntilLive(c, 's1');

    c.state.entries['s1']!.terminal.textInput('c');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final frames = inputFrames();
    expect(frames, hasLength(1));
    final payload =
        utf8.decode(base64Decode(frames.first['payload'] as String));
    expect(payload, 'c');
  });
}
