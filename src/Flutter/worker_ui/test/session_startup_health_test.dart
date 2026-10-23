import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/session_startup_health.dart';

void main() {
  test(
    'fresh startup alerts are visible and stale alerts from stopped components are ignored',
    () async {
      final home = Directory.systemTemp.createTempSync('startup-health');
      addTearDown(() => home.deleteSync(recursive: true));
      final file = File('${home.path}/.corterm/session-startup-health.json');
      file.parent.createSync();
      final now = DateTime.fromMillisecondsSinceEpoch(1000000);
      await file.writeAsString(
        jsonEncode({
          'updatedAt': 1000,
          'sessions': [
            {'sessionId': 's1', 'directory': '/workspace'},
          ],
        }),
      );
      final fresh = await readSessionStartupWarnings(
        homeDirectory: home.path,
        now: now,
      );
      expect(fresh.single.sessionId, 's1');
      expect(fresh.single.directory, '/workspace');
      expect(
        await readSessionStartupWarnings(
          homeDirectory: home.path,
          now: now.add(const Duration(seconds: 16)),
        ),
        isEmpty,
      );
      await file.writeAsString('incomplete');
      expect(
        await readSessionStartupWarnings(homeDirectory: home.path, now: now),
        isEmpty,
      );
    },
  );
}
