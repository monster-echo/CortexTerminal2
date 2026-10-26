import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';
import 'package:corterm_mobile/features/session/session_state.dart';

import '../test/replay_delta_test.dart' as fixtures;

import 'package:integration_test/integration_test.dart';

class DelayedStore extends fixtures.FakeStore {
  @override
  Future<void> setTerminalSeq(String key, int seq) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await super.setTerminalSeq(key, seq);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test(
    '100 immediate replay connections retain frames and reach live in order',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final sockets = <WebSocket>[];
      server.listen((req) async {
        final ws = await WebSocketTransformer.upgrade(req);
        sockets.add(ws);
        ws.add(jsonEncode({'type': 'replaying'}));
        ws.add(
          jsonEncode({
            'type': 'replay',
            'payload': base64Encode(utf8.encode('stress-output\r\n')),
          }),
        );
        ws.add(jsonEncode({'type': 'replayCompleted'}));
        ws.add(jsonEncode({'type': 'live'}));
        ws.listen((_) {});
      });
      try {
        for (var i = 0; i < 100; i++) {
          final controller = SessionController(fixtures.FakeRepo(), ({
            required sessionId,
            sinceSeq = 0,
          }) async {
            final socket = await TerminalSocket.connect(
              gatewayBaseUrl: 'http://127.0.0.1:${server.port}',
              token: 'fixture',
              sessionId: sessionId,
            );
            // Reproduce frames arriving before the controller subscribes.
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return socket;
          }, DelayedStore());
          try {
            await controller.open('stress-$i');
            for (var n = 0; n < 100; n++) {
              final entry = controller.state.entries['stress-$i']!;
              if (entry.connState == TerminalConnState.live &&
                  entry.hasReceivedOutput) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            final entry = controller.state.entries['stress-$i']!;
            expect(
              entry.connState,
              TerminalConnState.live,
              reason: 'iteration $i',
            );
            expect(entry.hasReceivedOutput, isTrue, reason: 'iteration $i');
            final text = List.generate(
              entry.terminal.buffer.height,
              (n) => entry.terminal.buffer.lines[n].getText(),
            ).join('\n');
            expect(text, contains('stress-output'), reason: 'iteration $i');
          } finally {
            controller.dispose();
          }
        }
      } finally {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
