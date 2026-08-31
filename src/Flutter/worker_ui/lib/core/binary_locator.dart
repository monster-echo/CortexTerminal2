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
/// GUI 启动不继承 shell PATH（Finder/Dock/资源管理器只给最小环境），所以：
/// ① `$CORTERM_HOME`/`$CORTEX_TERMINAL_HOME` → ② 默认 `~/.corterm/corterm`
/// （安装脚本的 INSTALL_DIR，App 内置 worker 也会自动装到这）→ ③ PATH 里找（尽力而为）。
/// 装 App 即带 worker，二者一体：ensureWorkerInstalled 保证 ② 处一定有一个
/// 支持 `--json` 的 worker（缺了装内置的，坏/旧了修内置的）。
/// Windows 用 `corterm.exe`/`cortap.exe`，home 目录用 `USERPROFILE`。
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
  final homeDir = _homeDir();
  if (homeDir != null) {
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

/// App 与 worker 一体：`~/.corterm` 里没有 worker 就装内置的；装过但不支持
/// `--json`（worker <0.5.16，install.ps1 / 手动安装的遗留）就用内置的修掉。
/// 幂等，每次启动跑一遍都安全。
Future<void> ensureWorkerInstalled() async {
  await ensureWorkerInstalledFrom(
    homeDir: _homeDir(),
    exePath: Platform.resolvedExecutable,
    isWindows: Platform.isWindows,
    isMacOS: Platform.isMacOS,
  );
}

/// 安装/修复入口，参数仅供测试注入（[ensureWorkerInstalled] 从当前进程取值）。
Future<void> ensureWorkerInstalledFrom({
  required String? homeDir,
  required String exePath,
  required bool isWindows,
  required bool isMacOS,
}) async {
  if (homeDir == null) return;
  final installDir = p.join(homeDir, '.corterm');
  final cortermName = isWindows ? 'corterm.exe' : 'corterm';

  final installedCorterm = File(p.join(installDir, cortermName));
  if (installedCorterm.existsSync()) {
    // 没有内置二进制（开发环境）就无从修起，直接用现有安装。
    if (bundledAssetPathFor(cortermName, exePath: exePath, isMacOS: isMacOS) == null) {
      return;
    }
    if (await _supportsJson(installedCorterm.path)) return;
    // 旧版：落到下面用内置 worker 覆盖修复。
  }
  await _installBundledWorker(installDir, exePath: exePath, isWindows: isWindows, isMacOS: isMacOS);
}

/// `status --help` 输出里 `--json` 选项（System.CommandLine 只显示首个别名，即裸
/// `json`）所在的行。探测用行首匹配：误报（把旧版判成支持）会让 App 继续用坏
/// 二进制，必须紧；漏报（把新版判成不支持）只是白修一次，无害。
final jsonOptionPattern = RegExp(r'^\s*json\b', multiLine: true);

/// 探测 CLI 是否支持 `--json`（App 的调用契约，worker ≥0.5.16）。
/// `status --help` 是纯解析调用——不执行命令逻辑、无网络副作用，新旧版本行为一致。
/// 结果按路径缓存：启动时 main/home_screen 会各 resolve 一遍，Windows 上单文件
/// exe 冷启动要一两秒，不能重复 spawn。
final _jsonProbeCache = <String, bool>{};

Future<bool> _supportsJson(String cortermPath) async {
  return _jsonProbeCache[cortermPath] ??= await _probeJson(cortermPath);
}

Future<bool> _probeJson(String cortermPath) async {
  try {
    final r = await Process.run(cortermPath, ['status', '--help']);
    return r.exitCode == 0 && jsonOptionPattern.hasMatch(r.stdout as String? ?? '');
  } catch (_) {
    return false;
  }
}

/// 把 App 内置的 corterm/cortap/appsettings.json 装到 [installDir]（幂等）。
/// appsettings.json 是用户的网关配置，只补缺不覆盖；二进制总是补齐/替换。
Future<void> _installBundledWorker(String installDir,
    {required String exePath, required bool isWindows, required bool isMacOS}) async {
  final cortermName = isWindows ? 'corterm.exe' : 'corterm';
  final cortapName = isWindows ? 'cortap.exe' : 'cortap';

  if (bundledAssetPathFor(cortermName, exePath: exePath, isMacOS: isMacOS) == null) {
    return; // 没内置二进制，交给安装/设置
  }

  try {
    Directory(installDir).createSync(recursive: true);
    for (final name in [cortermName, cortapName, 'appsettings.json']) {
      final src = bundledAssetPathFor(name, exePath: exePath, isMacOS: isMacOS);
      if (src == null) continue;
      final dest = File(p.join(installDir, name));
      if (name == 'appsettings.json' && dest.existsSync()) continue;
      _replaceFile(File(src), dest, isWindows: isWindows);
    }
  } catch (_) {
    // 装失败不阻塞，resolveBinaryPaths 还有 PATH 兜底
  }

  // Windows 上守护进程（计划任务）还挂着改名后的旧镜像跑，重启让新二进制生效。
  if (isWindows) {
    try {
      await Process.run(p.join(installDir, cortermName), ['restart', '--json']);
    } catch (_) {
      // 服务未安装（全新机器）等场景重启失败不阻塞；下次登录计划任务自然用新二进制。
    }
  }
}

/// 覆盖目标文件。Windows 对正在运行的 exe 持有镜像锁：删不掉、但可以改名。
/// 先把旧文件挪成 `.bak`（运行中的旧进程继续用改名后的镜像），再写入新文件
/// ——`corterm update` 自更新用的同一招。`.bak` 在旧进程退出前删不掉，尽力清理。
void _replaceFile(File src, File dest, {required bool isWindows}) {
  if (dest.existsSync() && isWindows) {
    final bak = File('${dest.path}.bak');
    if (bak.existsSync()) bak.deleteSync();
    dest.renameSync(bak.path);
    try {
      bak.deleteSync(); // 旧进程已退出时直接清掉
    } on FileSystemException {
      // 旧守护进程还挂在 .bak 镜像上，等它退出后，下次覆盖前的清理会带走它。
    }
  }
  dest.writeAsBytesSync(src.readAsBytesSync(), flush: true);
  if (!isWindows) {
    Process.runSync('chmod', ['+x', dest.path]);
  }
}

/// home 目录：Windows 没有 `HOME` 环境变量，用 `USERPROFILE`；其余平台 `HOME`。
String? homeDirOf(Map<String, String> env, {required bool isWindows}) {
  if (isWindows) {
    final profile = env['USERPROFILE'];
    return (profile != null && profile.isNotEmpty) ? profile : null;
  }
  final home = env['HOME'];
  return (home != null && home.isNotEmpty) ? home : null;
}

String? _homeDir() => homeDirOf(Platform.environment, isWindows: Platform.isWindows);

/// [exePath] 所在 App 的 flutter_assets 内置资产路径（发布/调试都成立）。
/// macOS 的 flutter_assets 在 .app 内部两个已知位置之一；Windows/Linux 就在
/// 可执行文件旁边的 `data/flutter_assets/`。
String? bundledAssetPathFor(String name,
    {required String exePath, required bool isMacOS}) {
  final exeDir = p.dirname(exePath);
  final rel = p.join('assets', 'bin', name);
  final candidates = isMacOS
      ? [
          p.normalize(p.join(exeDir, '..', 'Resources', 'flutter_assets', rel)),
          p.normalize(p.join(exeDir, '..', 'Frameworks', 'App.framework', 'Versions', 'A',
              'Resources', 'flutter_assets', rel)),
        ]
      : [p.join(exeDir, 'data', 'flutter_assets', rel)];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
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
