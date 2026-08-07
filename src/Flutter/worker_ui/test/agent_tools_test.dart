import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/agent_tools.dart';

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

  // 本机开发环境 claude 必然已装（~/.local/bin/claude），验证检测链路。
  test('claude is detected as installed on this machine', () async {
    final results = await detectAgentTools();
    final claude = results.firstWhere((r) => r.tool.id == 'claude');
    expect(claude.installed, isTrue);
  });
}
