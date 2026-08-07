import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/corterm_service.dart';

void main() {
  group('CortermService', () {
    test('throws CortermException when binary is missing', () {
      final svc = CortermService(
        cortermPath: '/nonexistent/corterm',
        cortapPath: '/nonexistent/cortap',
      );
      expect(svc.status(), throwsA(isA<CortermException>()));
    });

    test('parses status output from a fake executable', () async {
      if (Platform.isWindows) return; // fake script uses /bin/sh

      final dir = Directory.systemTemp.createTempSync('svc-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final script = File('${dir.path}/fake-corterm');
      script.writeAsStringSync(
        '#!/bin/sh\n'
        'if [ "\$1" = "status" ]; then\n'
        '  echo \'{"version":"0.5.14","pid":99,"uptime":"1d","gateway":"https://g",'
        '"workerId":"w","authenticated":true,"user":"u","authExpiry":"x",'
        '"gatewayInfo":{"version":"1.2.3","latestWorkerVersion":"0.5.15"},'
        '"updateAvailable":true,"workers":[]}\'\n'
        'else\n'
        '  echo "unexpected: \$1" >&2\n'
        '  exit 1\n'
        'fi\n',
      );
      await Process.run('chmod', ['+x', script.path]);

      final svc = CortermService(cortermPath: script.path, cortapPath: script.path);
      final status = await svc.status();

      expect(status.version, '0.5.14');
      expect(status.pid, 99);
      expect(status.authenticated, isTrue);
      expect(status.gatewayVersion, '1.2.3');
      expect(status.updateAvailable, isTrue);
      expect(status.workers, isEmpty);
    });
  });
}
