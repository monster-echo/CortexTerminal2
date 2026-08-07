import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/models.dart';

void main() {
  group('Status.fromJson', () {
    test('parses full authenticated status', () {
      final s = Status.fromJson({
        'version': '0.5.14',
        'pid': 95129,
        'uptime': '1d 2h 3m',
        'gateway': 'https://corterm.rwecho.top',
        'workerId': 'worker-host',
        'authenticated': true,
        'user': 'alice',
        'authExpiry': 'expires in 1d',
        'gatewayInfo': {'version': '1.2.3', 'latestWorkerVersion': '0.5.15'},
        'updateAvailable': true,
        'workers': [
          {
            'workerId': 'w1',
            'name': 'box',
            'hostname': 'h1',
            'operatingSystem': 'osx',
            'architecture': 'arm64',
            'version': '0.5.14',
            'isOnline': true,
            'lastSeenAtUtc': '2026-08-01T00:00:00Z',
            'sessionCount': 2,
            'cpuUsagePercent': 12.5,
            'memoryUsagePercent': 40.0,
          }
        ],
      });

      expect(s.version, '0.5.14');
      expect(s.pid, 95129);
      expect(s.authenticated, isTrue);
      expect(s.user, 'alice');
      expect(s.gatewayVersion, '1.2.3');
      expect(s.latestWorkerVersion, '0.5.15');
      expect(s.updateAvailable, isTrue);
      expect(s.workers, hasLength(1));
      expect(s.workers.first.displayName, 'box');
      expect(s.workers.first.isOnline, isTrue);
      expect(s.workers.first.cpuUsagePercent, 12.5);
    });

    test('parses unauthenticated status with nulls', () {
      final s = Status.fromJson({
        'version': '0.5.14',
        'pid': 1,
        'uptime': 'n/a',
        'gateway': 'https://g',
        'workerId': 'w',
        'authenticated': false,
        'user': null,
        'authExpiry': null,
        'gatewayInfo': null,
        'updateAvailable': false,
        'workers': [],
      });

      expect(s.authenticated, isFalse);
      expect(s.user, isNull);
      expect(s.gatewayVersion, isNull);
      expect(s.workers, isEmpty);
    });
  });

  group('DoctorResult.fromJson', () {
    test('parses checks and counts', () {
      final d = DoctorResult.fromJson({
        'checks': [
          {'name': 'Gateway URL', 'ok': true, 'detail': 'https://g'},
          {'name': 'Auth token present', 'ok': false, 'detail': 'missing'},
        ],
        'passedCount': 1,
        'failedCount': 1,
      });

      expect(d.checks, hasLength(2));
      expect(d.passedCount, 1);
      expect(d.failedCount, 1);
      expect(d.checks[1].ok, isFalse);
    });
  });

  group('UpdateCheck.fromJson', () {
    test('parses availability', () {
      final u = UpdateCheck.fromJson({
        'currentVersion': '0.5.14',
        'latestVersion': '0.5.15',
        'updateAvailable': true,
        'assetName': 'corterm-osx-arm64.tar.gz',
        'downloadUrl': 'https://dl',
      });

      expect(u.updateAvailable, isTrue);
      expect(u.assetName, 'corterm-osx-arm64.tar.gz');
    });
  });

  group('LoginStageData / UpdateProgress', () {
    test('login code stage', () {
      final stage = LoginStageData.fromJson({
        'stage': 'code',
        'verificationUri': 'https://corterm.rwecho.top/device',
        'userCode': 'ABCD-EFGH',
        'expiresInSeconds': 900,
        'pollIntervalSeconds': 5,
      });
      expect(stage.stage, 'code');
      expect(stage.userCode, 'ABCD-EFGH');
      expect(stage.isSuccess, isFalse);
      expect(stage.isError, isFalse);
    });

    test('update error stage', () {
      final p = UpdateProgress.fromJson({'stage': 'error', 'message': 'boom'});
      expect(p.isError, isTrue);
      expect(p.message, 'boom');
    });

    test('update download stage carries bytes', () {
      final p = UpdateProgress.fromJson({'stage': 'download', 'bytes': 2048, 'message': 'x.tar.gz'});
      expect(p.stage, 'download');
      expect(p.bytes, 2048);
    });
  });

  group('SessionSummary.fromJson', () {
    test('parses and derives crashed', () {
      final s = SessionSummary.fromJson({
        'sessionId': 'sess_abc',
        'kind': 'claude',
        'cwd': '/work',
        'startedAt': '2026-08-02T07:08:58+00:00',
        'endedAt': null,
        'pid': 28901,
        'eventCount': 1992,
        'lastEventAt': '2026-08-02T13:35:18+00:00',
        'isActive': false,
        'isCrashed': true,
      });
      expect(s.sessionId, 'sess_abc');
      expect(s.isCrashed, isTrue);
      expect(s.statusLabel, 'crashed');
    });
  });

  group('CortermEvent.formatted', () {
    test('renders prompt event', () {
      final e = CortermEvent.fromLine(
        '{"session_id":"s","agent_kind":"claude-code","event_type":"UserPromptSubmit",'
        '"payload":{"prompt":"fix the bug"},"ts":"2026-08-02T07:00:00+00:00"}',
      );
      expect(e.formatted, contains('UserPromptSubmit'));
      expect(e.formatted, contains('"fix the bug"'));
    });

    test('renders tool call with error marker', () {
      final e = CortermEvent.fromLine(
        '{"session_id":"s","agent_kind":"claude-code","event_type":"PostToolUse",'
        '"payload":{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"is_error":true}},'
        '"ts":"2026-08-02T07:00:00+00:00"}',
      );
      expect(e.formatted, contains('Bash'));
      expect(e.formatted, contains('ERROR'));
    });

    test('tolerates malformed payload', () {
      final e = CortermEvent.fromLine('not-json');
      expect(e.formatted, isNotEmpty);
    });
  });
}
