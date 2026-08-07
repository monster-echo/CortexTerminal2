import 'dart:io';

import 'package:path/path.dart' as p;

/// 常见 AI agent CLI 工具（claude / codex / gemini / opencode / aider）。
class AgentTool {
  const AgentTool({
    required this.id,
    required this.display,
    required this.binName,
    required this.installHint,
  });

  final String id; // 唯一标识
  final String display; // 展示名
  final String binName; // 二进制名
  final String installHint; // 安装提示（npm/pipx）
}

const List<AgentTool> agentTools = [
  AgentTool(
    id: 'claude',
    display: 'Claude Code',
    binName: 'claude',
    installHint: 'npm install -g @anthropic-ai/claude-code',
  ),
  AgentTool(
    id: 'codex',
    display: 'Codex',
    binName: 'codex',
    installHint: 'npm install -g @openai/codex',
  ),
  AgentTool(
    id: 'gemini',
    display: 'Gemini CLI',
    binName: 'gemini',
    installHint: 'npm install -g @google/gemini-cli',
  ),
  AgentTool(
    id: 'opencode',
    display: 'OpenCode',
    binName: 'opencode',
    installHint: 'npm install -g opencode-ai',
  ),
  AgentTool(
    id: 'aider',
    display: 'Aider',
    binName: 'aider',
    installHint: 'pipx install aider-chat',
  ),
];

class AgentToolStatus {
  const AgentToolStatus({
    required this.tool,
    required this.installed,
    this.version,
    this.path,
  });

  final AgentTool tool;
  final bool installed;
  final String? version;
  final String? path;
}

/// 检测常见 agent CLI 是否安装。
///
/// GUI 启动的 PATH 很受限，所以搜索三处：
/// ① App 自身 PATH 目录 → ② 常见安装目录（~/.local/bin、~/.npm-global/bin、
/// ~/.codex/bin、~/.opencode/bin、~/.claude/local、pnpm 等）→
/// ③ 登录 shell 的 PATH（`zsh -lic 'print -r -- $PATH'`，尽力而为，超时忽略），
///    这样能覆盖 nvm / pnpm 等用户自定义安装。
Future<List<AgentToolStatus>> detectAgentTools() async {
  final dirs = await _candidateDirs();
  final results = <AgentToolStatus>[];
  for (final tool in agentTools) {
    final bin = _findBinary(tool.binName, dirs);
    if (bin == null) {
      results.add(AgentToolStatus(tool: tool, installed: false));
      continue;
    }
    final version = await _versionOf(bin);
    results.add(AgentToolStatus(tool: tool, installed: true, version: version, path: bin));
  }
  return results;
}

Future<List<String>> _candidateDirs() async {
  final dirs = <String>{};
  final appPath = Platform.environment['PATH'] ?? '';
  for (final d in appPath.split(Platform.isWindows ? ';' : ':')) {
    if (d.isNotEmpty) dirs.add(d);
  }
  final home = Platform.environment['HOME'] ?? '';
  if (home.isNotEmpty) {
    dirs.addAll([
      p.join(home, '.local', 'bin'),
      p.join(home, '.npm-global', 'bin'),
      p.join(home, '.codex', 'bin'),
      p.join(home, '.opencode', 'bin'),
      p.join(home, '.claude', 'local'),
      p.join(home, '.claude', 'local', 'bin'),
      p.join(home, '.cargo', 'bin'),
      p.join(home, 'Library', 'pnpm'),
      p.join(home, '.config', 'gemini'),
    ]);
  }
  // 登录 shell 的 PATH（覆盖 nvm / pnpm 等自定义安装），尽力而为
  try {
    final shell = Platform.isWindows ? null : 'zsh';
    if (shell != null) {
      final r = await Process.run(shell, ['-lic', r'print -r -- $PATH'])
          .timeout(const Duration(seconds: 4));
      if (r.exitCode == 0) {
        for (final d in (r.stdout as String? ?? '').split(':')) {
          if (d.isNotEmpty) dirs.add(d);
        }
      }
    }
  } catch (_) {
    // 拿不到就只用前两类目录
  }
  return dirs.toList();
}

String? _findBinary(String binName, List<String> dirs) {
  final names = Platform.isWindows
      ? ['$binName.exe', '$binName.cmd', '$binName.bat']
      : [binName];
  for (final dir in dirs) {
    for (final n in names) {
      final f = File(p.join(dir, n));
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}

Future<String?> _versionOf(String bin) async {
  try {
    final r = await Process.run(bin, ['--version'])
        .timeout(const Duration(seconds: 5));
    if (r.exitCode == 0) {
      final out = (r.stdout as String? ?? '').trim();
      if (out.isNotEmpty) return out.split('\n').first.trim();
    }
  } catch (_) {
    // 版本拿不到不影响"已安装"判定
  }
  return null;
}
