import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/corterm_service.dart';

/// E2E：用真实发布的 corterm/cortap 二进制（/tmp/corterm-test，含 --json 支持）走一遍解析。
/// 二进制不存在时自动跳过 —— 这是本地验证用的集成测试，不是 CI 常规用例。
void main() {
  test('real corterm status/doctor/sessions parse correctly', () async {
    const base = '/tmp/corterm-test';
    if (!File('$base/corterm').existsSync() || !File('$base/cortap').existsSync()) {
      markTestSkipped('published binaries not present at $base');
      return;
    }

    final svc = CortermService(cortermPath: '$base/corterm', cortapPath: '$base/cortap');

    final status = await svc.status();
    expect(status.version, isNotEmpty);
    expect(status.gateway, isNotEmpty);
    expect(status.workers, isA<List<dynamic>>());

    final doctor = await svc.doctor();
    expect(doctor.checks, isNotEmpty);

    final sessions = await svc.sessions();
    expect(sessions, isA<List<dynamic>>());
  });
}
