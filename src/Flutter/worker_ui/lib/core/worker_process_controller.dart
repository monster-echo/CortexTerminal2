import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'binary_locator.dart';

/// [WorkerProcessController] spawn 前解析 corterm 二进制的函数签名。
typedef BinaryPathResolver = Future<BinaryPaths?> Function();

/// worker 托管生命周期，供 UI 展示（如 dashboard 的「启动中」态）。
enum WorkerRunState {
  /// 未托管（其他平台 / 尚未 start / 已 stop）。
  stopped,

  /// 正在拉起（spawn / 迁移 / 杀旧拉新）。
  starting,

  /// 守护进程在跑（自己 spawn 的或采纳的）。
  running,

  /// 守护进程退出，退避等待重启。
  backingOff,
}

/// macOS：App 直接托管 worker 子进程 —— 裸调用 `corterm`（无参数）就是前台
/// 守护进程，替代 LaunchAgent + launchctl（见 Program.cs RunMacServiceCommand 的
/// 脆弱性注释）。托盘常驻 + 开机启动（launch_at_startup）保证可用性；
/// 托盘退出 = 停止远程访问。
///
/// 守护进程唯一特征是 argv 为空：`ps` 扫描里命令行以 `/corterm` 结尾。
/// status/doctor/update 等瞬态 CLI 同名但带参数，不会被误匹配。
/// Windows / Linux 同样由桌面 App 托管，不依赖独立 CLI 的启动任务。
class WorkerProcessController {
  WorkerProcessController._()
    : homeDirOverride = null,
      daemonLister = null,
      processRunner = null,
      binaryPathResolver = null,
      adoptPollInterval = const Duration(seconds: 30);

  static final instance = WorkerProcessController._();

  /// 测试注入：仿 [ensureWorkerInstalledFrom] 惯例。
  WorkerProcessController({
    this.homeDirOverride,
    this.daemonLister,
    this.processRunner,
    this.binaryPathResolver,
    this.adoptPollInterval = const Duration(seconds: 30),
  });

  static const _label = 'com.corterm.worker';
  static const _logName = 'corterm.log'; // 与 launchd 时代 StandardOutPath 同位置

  final String? homeDirOverride;
  final Future<String> Function()? daemonLister;
  final Future<ProcessResult> Function(String executable, List<String> args)?
  processRunner;
  final BinaryPathResolver? binaryPathResolver;

  /// 采纳进程的存活轮询周期。外部 pid 拿不到退出事件，只能轮询；
  /// 轮询间隔可注入以便测试。
  final Duration adoptPollInterval;

  Process? _child;
  int? _adoptedPid;
  bool _stopRequested = false;
  int _backoffSeconds = 1;
  DateTime? _spawnedAt;
  Timer? _restartTimer;
  Timer? _adoptPollTimer;
  IOSink? _logSink;

  /// 当前托管状态（UI 可监听）。
  final runState = ValueNotifier<WorkerRunState>(WorkerRunState.stopped);

  String? get _home =>
      homeDirOverride ??
      homeDirOf(Platform.environment, isWindows: Platform.isWindows);

  /// 拉起守护进程（幂等）。[forceRestartRunning]：已发现运行中的守护进程时
  /// 杀掉重拉 —— [ensureWorkerInstalled] 刚修复/替换过二进制时传 true，
  /// 否则旧镜像进程会一直占用到下次重启。
  Future<void> start({bool forceRestartRunning = false}) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    try {
      if (_child != null) return;
      _stopRequested = false;
      runState.value = WorkerRunState.starting;
      if (!await _migrateLegacyService()) {
        _log('旧启动任务无法停用，跳过 spawn 防止重复运行');
        runState.value = WorkerRunState.stopped;
        return;
      }
      final pid = await findDaemonPid();
      if (pid != null) {
        if (!forceRestartRunning) {
          // 采纳已运行的守护进程（App 崩溃后的孤儿、用户手动 corterm start）。
          // 外部 pid 拿不到退出事件，轮询接管：它死了继续由本 App 补拉，
          // 否则就是"采纳后失管"，复活旧架构的永久离线。
          _adoptedPid = pid;
          _startAdoptPolling(pid);
          runState.value = WorkerRunState.running;
          _log('daemon already running (pid $pid)，采纳并纳入监控');
          return;
        }
        await _killPidBestEffort(pid);
      }
      await _spawn();
    } catch (e) {
      // 启动是 best-effort（同旧 _ensureWorkerService 惯例）：失败不阻塞 UI，
      // dashboard 会从 status 拉不到而展示离线；记录日志供诊断。
      runState.value = WorkerRunState.stopped;
      _log('start 失败: $e');
    }
  }

  /// Choosing the desktop launcher transfers lifecycle ownership from the CLI service.
  /// Keep the old task definition so a CLI installation can re-enable its own mode.
  Future<bool> _migrateLegacyService() async {
    if (Platform.isWindows) {
      final query = await Process.run('schtasks', [
        '/Query',
        '/TN',
        'Corterm Worker',
      ]);
      if (query.exitCode != 0) return true;
      final disabled = await Process.run('schtasks', [
        '/Change',
        '/TN',
        'Corterm Worker',
        '/Disable',
      ]);
      if (disabled.exitCode != 0) {
        _log('Cannot disable legacy worker task: ${disabled.stderr}');
        return false;
      }
      await Process.run('schtasks', ['/End', '/TN', 'Corterm Worker']);
      final legacyPid = await findDaemonPid();
      if (legacyPid != null) await _killPidBestEffort(legacyPid);
      return true;
    }
    if (Platform.isLinux) {
      await _run('systemctl', ['--user', 'disable', '--now', 'corterm-worker']);
      return true;
    }
    return migrateLegacyLaunchAgent();
  }

  /// 一次性迁移：旧的 LaunchAgent 托管模式 → App 托管。plist 存在则
  /// unload + remove + 删除，并轮询旧进程消失（unload 后 launchd 收割有延迟）。
  /// 返回 false（plist 删不掉）时调用方不得 spawn，否则 launchd KeepAlive
  /// 与子进程双实例。
  Future<bool> migrateLegacyLaunchAgent() async {
    if (!Platform.isMacOS) return true;
    final home = _home;
    if (home == null) return true;
    final plist = File(
      p.join(home, 'Library', 'LaunchAgents', '$_label.plist'),
    );
    if (!plist.existsSync()) return true;

    await _run('launchctl', ['unload', plist.path]);
    await _run('launchctl', ['remove', _label]);
    try {
      plist.deleteSync();
    } on FileSystemException catch (e) {
      _log('删除 LaunchAgent plist 失败: $e');
      return false;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (await findDaemonPid() == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // 旧进程 5s 后仍在：返回 true 让 start() 的采纳逻辑接管它，不 spawn。
    return true;
  }

  /// 运行中的守护进程 pid（argv 为空的 corterm），没有则 null。
  Future<int?> findDaemonPid() async {
    if (Platform.isWindows && daemonLister == null) {
      return _findWindowsDaemonPid();
    }
    final output = await _listProcesses();
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final space = trimmed.indexOf(' ');
      if (space <= 0) continue;
      final pid = int.tryParse(trimmed.substring(0, space));
      if (pid == null) continue;
      final command = trimmed.substring(space + 1).trimRight();
      if (command.endsWith('/corterm')) return pid;
    }
    return null;
  }

  Future<int?> _findWindowsDaemonPid({int? onlyPid}) async {
    final paths = await (binaryPathResolver ?? resolveBinaryPaths)();
    if (paths == null) return null;
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Get-CimInstance Win32_Process -Filter \"Name='corterm.exe'\" | Select-Object ProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress",
    ]);
    if (result.exitCode != 0) {
      throw StateError('Cannot inspect worker processes: ${result.stderr}');
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) return null;
    return windowsWorkerDaemonPidFromJson(
      output,
      executablePath: paths.corterm,
      onlyPid: onlyPid,
    );
  }

  /// 停止托管并杀掉守护进程。只接托盘退出 —— 绝不能挂到全局 exit 钩子上：
  /// SelfUpdater 更新 UI 自身时也会 exit，worker 必须存活。
  Future<void> stop() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    _stopRequested = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    _adoptPollTimer?.cancel();
    _adoptPollTimer = null;
    runState.value = WorkerRunState.stopped;
    final child = _child;
    if (child != null) {
      _child = null;
      child.kill(); // SIGTERM；worker Generic Host 优雅退出
      try {
        await child.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode; // 收尸防 zombie
      }
    } else if (_adoptedPid != null) {
      final pid = _adoptedPid!;
      _adoptedPid = null;
      await _killPidBestEffort(pid);
    }
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
  }

  /// 重启（worker 更新完成后由调用方触发）。start() 内部会重跑 LaunchAgent
  /// 迁移 —— legacy 路径的 update 若重建了 plist，这里收敛回 App 托管。
  Future<void> restart() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    await stop();
    await start();
  }

  // ── 内部实现 ──

  /// 采纳进程存活轮询：消失（且非本次 stop）则补拉，维持"App 活着就有 worker"。
  void _startAdoptPolling(int pid) {
    _adoptPollTimer?.cancel();
    _adoptPollTimer = Timer.periodic(adoptPollInterval, (timer) async {
      if (_stopRequested || _adoptedPid != pid) {
        timer.cancel();
        return;
      }
      if (await _pidIsDaemon(pid)) return;
      timer.cancel();
      _adoptedPid = null;
      _log('采纳的守护进程（pid $pid）已退出，补拉');
      await _spawn();
    });
  }

  Future<void> _spawn() async {
    final resolve = binaryPathResolver ?? resolveBinaryPaths;
    final paths = await resolve();
    if (paths == null) {
      runState.value = WorkerRunState.stopped;
      _log('找不到 corterm 二进制，跳过 spawn');
      return;
    }
    final home = _home;
    if (home == null) {
      runState.value = WorkerRunState.stopped;
      return;
    }

    Directory(p.join(home, '.corterm')).createSync(recursive: true);
    final logFile = File(p.join(home, '.corterm', _logName));
    _rotateLogIfNeeded(logFile);
    await _logSink?.flush();
    await _logSink?.close(); // respawn 循环复用本方法：先关旧 sink 防 fd 泄漏
    _logSink = logFile.openWrite(mode: FileMode.append);

    final spawnedAt = DateTime.now();
    final proc = await Process.start(
      paths.corterm,
      const [],
      workingDirectory: home, // 与 launchd plist 的 WorkingDirectory 一致
      environment: {
        'CORTERM_LIFECYCLE_OWNER': 'desktop',
        // FSEvents can block while watching homes on external macOS volumes.
        if (Platform.isMacOS) 'DOTNET_USE_POLLING_FILE_WATCHER': '1',
      },
    );
    _child = proc;
    _adoptedPid = null;
    _adoptPollTimer?.cancel(); // 监管权移交 exitCode future
    _adoptPollTimer = null;
    _stopRequested = false;
    _spawnedAt = spawnedAt;
    runState.value = WorkerRunState.running;
    // stdout/stderr 必须从 spawn 起持续泵走，否则 worker 写满管道会阻塞。
    _logSink!.writeln('[$spawnedAt] spawned pid ${proc.pid}');
    proc.stdout.listen(_logSink!.add);
    proc.stderr.listen(_logSink!.add);
    unawaited(proc.exitCode.then((code) => _onChildExit(proc, code)));
  }

  Future<void> _onChildExit(Process proc, int code) async {
    if (_child != proc) return;
    _child = null;
    await _logSink?.flush();
    final stableFor = _spawnedAt == null
        ? Duration.zero
        : DateTime.now().difference(_spawnedAt!);
    if (stableFor > const Duration(seconds: 60)) _backoffSeconds = 1;
    _log('worker 退出（code $code），${_backoffSeconds}s 后重启');
    if (_stopRequested) {
      runState.value = WorkerRunState.stopped;
      return;
    }
    runState.value = WorkerRunState.backingOff;
    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(seconds: _backoffSeconds), () async {
      _backoffSeconds = min(_backoffSeconds * 2, 30);
      // 别人（手动 CLI 等）已拉起就采纳，防双实例。
      if (_child != null) return;
      if (await findDaemonPid() != null) return;
      await _spawn();
    });
  }

  /// 杀外部 pid：先复核它仍是守护进程（防 pid 复用误杀），TERM → 3s → KILL。
  Future<void> _killPidBestEffort(int pid) async {
    if (!await _pidIsDaemon(pid)) return;
    if (Platform.isWindows) {
      await _run('taskkill', ['/PID', '$pid', '/F']);
      return;
    }
    await _run('kill', ['-TERM', '$pid']);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _pidIsDaemon(pid)) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _run('kill', ['-KILL', '$pid']);
  }

  Future<bool> _pidIsDaemon(int pid) async {
    if (Platform.isWindows) {
      return await _findWindowsDaemonPid(onlyPid: pid) != null;
    }
    final r = await _run('ps', ['-p', '$pid', '-o', 'command=']);
    return r.trimRight().endsWith('/corterm');
  }

  Future<String> _listProcesses() async {
    final lister = daemonLister;
    if (lister != null) return lister();
    final runner = processRunner;
    final r = runner != null
        ? await runner('ps', ['-ww', '-axo', 'pid=,command='])
        : await Process.run('ps', ['-ww', '-axo', 'pid=,command=']);
    return r.stdout as String? ?? '';
  }

  /// launchctl / kill 是尽力而为：失败只记日志（launchctl unload 未加载的
  /// job 会非零退出，属正常路径）。
  Future<String> _run(String executable, List<String> args) async {
    try {
      final runner = processRunner;
      final r = runner != null
          ? await runner(executable, args)
          : await Process.run(executable, args);
      return r.stdout as String? ?? '';
    } catch (e) {
      _log('$executable ${args.join(' ')} 失败: $e');
      return '';
    }
  }

  void _rotateLogIfNeeded(File logFile) {
    if (!logFile.existsSync()) return;
    if (logFile.lengthSync() <= 10 * 1024 * 1024) return;
    final old = File('${logFile.path}.1');
    if (old.existsSync()) old.deleteSync();
    logFile.renameSync(old.path);
  }

  void _log(String message) {
    debugPrint('[WorkerProcessController] $message');
  }
}

/// Match only bare workers at the resolved worker path, excluding the desktop GUI
/// and short-lived CLI calls even though they share the same executable name.
@visibleForTesting
int? windowsWorkerDaemonPidFromJson(
  String output, {
  required String executablePath,
  int? onlyPid,
}) {
  final decoded = jsonDecode(output);
  final rows = decoded is List ? decoded : [decoded];
  final expected = executablePath.toLowerCase();
  for (final row in rows) {
    final id = row['ProcessId'] as int;
    if (onlyPid != null && id != onlyPid) continue;
    final executable = (row['ExecutablePath'] as String? ?? '').toLowerCase();
    final command = (row['CommandLine'] as String? ?? '')
        .trim()
        .replaceAll('"', '')
        .toLowerCase();
    // Match the exact worker path and a bare invocation, never the desktop GUI
    // (also named Corterm.exe) or transient login/status/update commands.
    if ((executable == expected || executable == '$expected.bak') &&
        (command == expected || command == executable)) {
      return id;
    }
  }
  return null;
}
