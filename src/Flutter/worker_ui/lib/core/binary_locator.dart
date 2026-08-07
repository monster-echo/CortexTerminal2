import 'dart:io';

import 'package:path/path.dart' as p;

/// corterm / cortap 二进制路径对。
class BinaryPaths {
  const BinaryPaths({required this.corterm, required this.cortap});

  final String corterm;
  final String cortap;
}

/// 解析 corterm/cortap 绝对路径。
///
/// GUI 启动不继承 shell PATH（Finder/Dock 只给最小环境），所以：
/// ① `$CORTERM_HOME`/`$CORTEX_TERMINAL_HOME` → ② 默认 `~/.corterm/corterm`
/// （install.sh 的 INSTALL_DIR，App 内置 worker 也会自动装到这）→ ③ PATH 里找（尽力而为）。
/// 装 App 即带 worker，二者一体。
/// Windows 用 `corterm.exe`/`cortap.exe`。
Future<BinaryPaths?> resolveBinaryPaths() async {
  await ensureWorkerInstalled();

  final isWindows = Platform.isWindows;
  final cortermName = isWindows ? 'corterm.exe' : 'corterm';
  final cortapName = isWindows ? 'cortap.exe' : 'cortap';

  final candidates = <String>[];
  final envHome =
      Platform.environment['CORTERM_HOME'] ?? Platform.environment['CORTEX_TERMINAL_HOME'];
  if (envHome != null && envHome.isNotEmpty) {
    candidates.add(p.join(envHome, cortermName));
  }
  final homeDir = Platform.environment['HOME'];
  if (homeDir != null && homeDir.isNotEmpty) {
    candidates.add(p.join(homeDir, '.corterm', cortermName));
  }

  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      final dir = p.dirname(candidate);
      return BinaryPaths(corterm: candidate, cortap: p.join(dir, cortapName));
    }
  }

  // PATH 兜底（GUI 下通常解析不到，仅当从终端启动时有效）
  final pathEntry = await _which(cortermName);
  if (pathEntry != null) {
    final dir = p.dirname(pathEntry);
    return BinaryPaths(corterm: pathEntry, cortap: p.join(dir, cortapName));
  }

  return null;
}

/// App 与 worker 一体：如果 `~/.corterm` 里没有 worker，就把 App 内置的
/// corterm/cortap/appsettings.json 装过去（幂等，已有 worker 则不覆盖）。
Future<void> ensureWorkerInstalled() async {
  final homeDir = Platform.environment['HOME'];
  if (homeDir == null || homeDir.isEmpty) return;
  final installDir = p.join(homeDir, '.corterm');
  final isWindows = Platform.isWindows;
  final cortermName = isWindows ? 'corterm.exe' : 'corterm';
  final cortapName = isWindows ? 'cortap.exe' : 'cortap';

  final installedCorterm = File(p.join(installDir, cortermName));
  if (installedCorterm.existsSync()) return;

  final bundledCorterm = _bundledAssetPath(cortermName);
  if (bundledCorterm == null) return; // 没内置二进制，交给安装/设置

  try {
    Directory(installDir).createSync(recursive: true);
    for (final name in [cortermName, cortapName, 'appsettings.json']) {
      final src = _bundledAssetPath(name);
      if (src == null) continue;
      final dest = File(p.join(installDir, name));
      // 已存在的 appsettings.json 是用户的网关配置，保留不覆盖；二进制则总是补齐。
      if (name == 'appsettings.json' && dest.existsSync()) continue;
      dest.writeAsBytesSync(File(src).readAsBytesSync(), flush: true);
      if (!isWindows && name != 'appsettings.json') {
        Process.runSync('chmod', ['+x', dest.path]);
      }
    }
  } catch (_) {
    // 装失败不阻塞，resolveBinaryPaths 还有 PATH 兜底
  }
}

/// App bundle 里 `flutter_assets/assets/bin/` 的路径（发布/调试都成立）。
/// flutter_assets 的位置随 Flutter 版本变化：老的在 Contents/Resources/，新的在
/// Contents/Frameworks/App.framework/Versions/A/Resources/ 下，两个都查。
String? _bundledAssetPath(String name) {
  final exe = Platform.resolvedExecutable;
  final contents = p.dirname(p.dirname(exe)); // <app>/Contents
  final appRoot = p.dirname(contents);        // <app>
  final rel = p.join('assets', 'bin', name);
  final candidates = [
    p.join(contents, 'Resources', 'flutter_assets', rel),
    p.join(appRoot, 'Contents', 'Frameworks', 'App.framework', 'Versions', 'A',
        'Resources', 'flutter_assets', rel),
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.path;
  }
  return null;
}

Future<String?> _which(String name) async {
  final cmd = Platform.isWindows ? 'where' : 'which';
  try {
    final result = await Process.run(cmd, [name]);
    if (result.exitCode != 0) return null;
    final first = (result.stdout as String? ?? '').split('\n').firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );
    return first.trim().isEmpty ? null : first.trim();
  } catch (_) {
    return null;
  }
}
