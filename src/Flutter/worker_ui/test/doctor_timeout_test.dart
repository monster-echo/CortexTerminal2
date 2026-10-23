import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/corterm_service.dart';

void main() {
  test(
    'a stalled doctor returns an actionable timeout without waiting indefinitely',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'corterm-doctor-timeout',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final executable = File('${root.path}/doctor');
      executable.writeAsStringSync('#!/bin/sh\nexec sleep 60\n');
      await Process.run('chmod', ['+x', executable.path]);
      final service = CortermService(
        cortermPath: executable.path,
        diagnosticTimeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        service.doctor(directory: root.path),
        throwsA(
          isA<CortermException>().having(
            (e) => e.message,
            'message',
            'diagnostic-timeout',
          ),
        ),
      );
    },
    skip: Platform.isWindows,
  );
}
