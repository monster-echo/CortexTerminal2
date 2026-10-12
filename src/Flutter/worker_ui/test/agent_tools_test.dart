import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:worker_ui/core/agent_tools.dart';
import 'package:worker_ui/core/binary_locator.dart';

void main() {
  test('agentTools covers the common agent CLIs', () {
    expect(
      agentTools.map((t) => t.id),
      containsAll(['claude', 'codex', 'gemini', 'opencode', 'aider']),
    );
    for (final t in agentTools) {
      expect(t.binName, isNotEmpty);
      expect(t.installHint, isNotEmpty);
    }
  });

  test('detectAgentTools returns a status per tool; installed paths exist', () async {
    final results = await detectAgentTools();
    expect(results, hasLength(agentTools.length));
    for (final r in results) {
      if (r.installed) {
        expect(r.path, isNotNull, reason: '${r.tool.id} 应带路径');
        expect(File(r.path!).existsSync(), isTrue);
      }
    }
  });

  // 本机开发环境 claude 已装时验证检测链路；CI runner 没装则跳过（不做环境假设）。
  test('claude is detected as installed on this machine', () async {
    final home = homeDirOf(Platform.environment, isWindows: Platform.isWindows);
    final marker = home == null
        ? null
        : File(p.join(home, '.local', 'bin', Platform.isWindows ? 'claude.exe' : 'claude'));
    if (marker == null || !marker.existsSync()) return;
    final results = await detectAgentTools();
    final claude = results.firstWhere((r) => r.tool.id == 'claude');
    expect(claude.installed, isTrue);
  });
}
