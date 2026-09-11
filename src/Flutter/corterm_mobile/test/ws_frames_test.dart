import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/ws/ws_frames.dart';

void main() {
  group('WsFrames.parseServerFrame', () {
    test('parses replaying / replayCompleted / live / detached', () {
      expect(WsFrames.parseServerFrame('{"type":"replaying"}'), isA<ReplayingFrame>());
      expect(WsFrames.parseServerFrame('{"type":"replayCompleted"}'), isA<ReplayCompletedFrame>());
      expect(WsFrames.parseServerFrame('{"type":"live"}'), isA<LiveFrame>());
      expect(WsFrames.parseServerFrame('{"type":"detached"}'), isA<DetachedFrame>());
    });

    test('parses replay frame with base64 payload', () {
      final payload = base64Encode(utf8.encode('hello \x1b[32mgreen\x1b[0m'));
      final frame = WsFrames.parseServerFrame(
        jsonEncode({'type': 'replay', 'sessionId': 's1', 'stream': 'stdout', 'payload': payload}),
      ) as ReplayFrame;
      expect(utf8.decode(frame.bytes), contains('green'));
      expect(frame.stream, 'stdout');
    });

    test('parses output frame and empty payload', () {
      final frame = WsFrames.parseServerFrame('{"type":"output","payload":""}') as OutputFrame;
      expect(frame.bytes, isEmpty);
    });

    test('parses exited with code and reason', () {
      final frame = WsFrames.parseServerFrame(
        '{"type":"exited","exitCode":0,"reason":"done"}',
      ) as ExitedFrame;
      expect(frame.exitCode, 0);
      expect(frame.reason, 'done');
    });

    test('parses error frame', () {
      final frame = WsFrames.parseServerFrame(
        '{"type":"error","code":"session-not-found","message":"gone"}',
      ) as ErrorFrame;
      expect(frame.code, 'session-not-found');
      expect(frame.message, 'gone');
    });

    test('parses latencyAck', () {
      final frame = WsFrames.parseServerFrame(
        '{"type":"latencyAck","probeId":"p1","clientTime":1000,"serverTime":1005}',
      ) as LatencyAckFrame;
      expect(frame.probeId, 'p1');
      expect(frame.clientTime, 1000);
    });

    test('parses displaced frame (协议预留：第二客户端挤掉)', () {
      final frame = WsFrames.parseServerFrame('{"type":"displaced"}') as DisplacedFrame;
      expect(frame.reason, isNull);
      final withReason =
          WsFrames.parseServerFrame('{"type":"displaced","reason":"superseded"}') as DisplacedFrame;
      expect(withReason.reason, 'superseded');
    });

    test('throws on unknown type (no silent swallow)', () {
      expect(
        () => WsFrames.parseServerFrame('{"type":"wat"}'),
        throwsFormatException,
      );
    });

    test('throws on malformed JSON', () {
      expect(() => WsFrames.parseServerFrame('not json'), throwsFormatException);
    });
  });

  group('WsFrames client frames', () {
    test('input encodes utf8 payload as base64', () {
      final raw = WsFrames.input('ls 中文\n');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['type'], 'input');
      expect(utf8.decode(base64Decode(decoded['payload'] as String)), 'ls 中文\n');
    });

    test('resize carries columns/rows', () {
      final decoded = jsonDecode(WsFrames.resize(columns: 120, rows: 40)) as Map<String, dynamic>;
      expect(decoded, {'type': 'resize', 'columns': 120, 'rows': 40});
    });

    test('detach/close/ping/latencyProbe shapes', () {
      expect(WsFrames.detachFrame, '{"type":"detach"}');
      expect(WsFrames.closeFrame, '{"type":"close"}');
      expect(jsonDecode(WsFrames.ping(123)), {'type': 'ping', 'timestamp': 123});
      final probe = jsonDecode(WsFrames.latencyProbe('x', 456)) as Map<String, dynamic>;
      expect(probe['probeId'], 'x');
      expect(probe['clientTime'], 456);
    });

    test('buildUri upgrades https→wss and carries query auth', () {
      final uri = WsFrames.buildUri(
        gatewayBaseUrl: 'https://gw.example.com',
        token: 'jwt',
        sessionId: 's1',
      );
      expect(uri.scheme, 'wss');
      expect(uri.host, 'gw.example.com');
      expect(uri.path, '/ws/terminal');
      expect(uri.queryParameters['token'], 'jwt');
      expect(uri.queryParameters['sessionId'], 's1');
      // 能力协商：声明 displaced，gateway 才会向本连接发挤占帧。
      expect(uri.queryParameters['caps'], 'displaced');
    });

    test('buildUri keeps explicit port', () {
      final uri = WsFrames.buildUri(
        gatewayBaseUrl: 'http://10.0.0.2:5000',
        token: 'jwt',
        sessionId: 's1',
      );
      expect(uri.scheme, 'ws');
      expect(uri.port, 5000);
    });
  });
}
