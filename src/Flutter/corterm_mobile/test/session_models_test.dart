import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/models/session.dart';

SessionSummary summaryFrom(Map<String, dynamic> json) => SessionSummary.fromJson(json);

Map<String, dynamic> baseJson() => {
      'sessionId': 'e28fa11b-1234-5678-9abc-def012345678',
      'name': '',
      'workerId': 'w1',
      'workerName': 'Mac mini',
      'status': 'DetachedGracePeriod',
      'createdAtUtc': '2026-09-10T08:00:00Z',
      'lastActivityAtUtc': '2026-09-10T09:30:00Z',
    };

void main() {
  group('SessionSummary.fromJson', () {
    test('parses gateway summary with workerName', () {
      final s = summaryFrom(baseJson());
      expect(s.sessionId, 'e28fa11b-1234-5678-9abc-def012345678');
      expect(s.workerName, 'Mac mini');
      expect(s.status, SessionStatus.detachedGracePeriod);
      expect(s.status.isAlive, isTrue);
    });

    test('accepts createdAt (non-Utc) key variant', () {
      final json = baseJson()
        ..remove('createdAtUtc')
        ..['createdAt'] = '2026-09-10T08:00:00Z';
      expect(summaryFrom(json).createdAt.year, 2026);
    });

    test('accepts attachmentState fallback key', () {
      final json = baseJson()..remove('status')..['attachmentState'] = 'Attached';
      expect(summaryFrom(json).status, SessionStatus.attached);
    });

    test('throws on missing sessionId', () {
      final json = baseJson()..remove('sessionId');
      expect(() => summaryFrom(json), throwsFormatException);
    });

    test('throws on unknown status (no silent fallback)', () {
      final json = baseJson()..['status'] = 'Whatever';
      expect(() => summaryFrom(json), throwsFormatException);
    });
  });

  group('display name priority (§55)', () {
    test('user-defined name wins', () {
      final s = summaryFrom(baseJson()..['name'] = 'Corterm Dev');
      expect(s.displayName, 'Corterm Dev');
    });

    test('inferredTitle second', () {
      final s = summaryFrom(baseJson()..['inferredTitle'] = 'fix: scrollback');
      expect(s.displayName, 'fix: scrollback');
    });

    test('agent label third, never a bare uuid', () {
      final s = summaryFrom(baseJson()..['agentKind'] = 'claude-code');
      expect(s.displayName, 'Claude Code');
    });

    test('short id last', () {
      final s = summaryFrom(baseJson());
      expect(s.displayName, startsWith('Session e28fa11b'));
      expect(s.displayName, isNot(contains('-1234')));
    });
  });

  group('status grouping (§15)', () {
    test('running vs ended', () {
      final alive = summaryFrom(baseJson()..['status'] = 'Recovering');
      expect(alive.status.isRunning, isTrue);
      final ended = summaryFrom(baseJson()..['status'] = 'Exited');
      expect(ended.status.isRunning, isFalse);
    });
  });

  group('AgentKind labels', () {
    test('maps known agent kinds', () {
      expect(agentKindFrom('codex').label, 'Codex');
      expect(agentKindFrom('opencode').label, 'OpenCode');
      expect(agentKindFrom('none').label, 'Shell');
      expect(agentKindFrom(null), AgentKind.unknown);
    });
  });
}
