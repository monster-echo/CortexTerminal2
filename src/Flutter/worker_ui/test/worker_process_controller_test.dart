import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:worker_ui/core/binary_locator.dart';
import 'package:worker_ui/core/corterm_service.dart';
import 'package:worker_ui/core/worker_process_controller.dart';

/// 常驻型 fake daemon：TERM 优雅退出、输出一行 started、循环睡眠。
const _fakeDaemon = '#!/bin/sh\n'
    'trap \'exit 0\' TERM\n'
    'echo started\n'
    'while :; do sleep 1; done\n';

Directory _tempHome() {
  final dir = Directory.systemTemp.createTempSync('wpc-test');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 只读目录（迁移失败用例）里跑过的进程句柄释放有延迟，尽力清理。
    }
  });
  return dir;
}

File _daemonScript(Directory home) {
  final file = File('${home.path}/.corterm/corterm');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(_fakeDaemon);
  Process.runSync('chmod', ['+x', file.path]);
  return file;
}

String _readLog(Directory home) {
  final log = File('${home.path}/.corterm/corterm.log');
  return log.existsSync() ? log.readAsStringSync() : '';
}

/// 等到日志出现 [marker]（spawn/退出写日志是异步的）。
Future<String> _waitForLog(Directory home, Pattern marker,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final log = _readLog(home);
    if (log.contains(marker)) return log;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('log never contained $marker; got:\n${_readLog(home)}');
}

void main() {
  test('start spawns daemon and writes log header', () async {
    if (!Platform.isMacOS) return; // fake script + ps 探测是 macOS 路径
    final home = _tempHome();
    final daemon = _daemonScript(home);
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async => '',
      binaryPathResolver: () async => BinaryPaths(corterm: daemon.path),
    );
    addTearDown(controller.stop);

    await controller.start();

    final log = await _waitForLog(home, 'spawned pid');
    expect(log, contains('[20'));
  });

  test('findDaemonPid matches bare invocation only', () async {
    const ps = '  123 /Applications/Corterm.app/Contents/MacOS/Corterm\n'
        '  456 /Users/x/.corterm/corterm\n'
        '  789 /Users/x/.corterm/corterm status --json\n'
        '  101 /Users/x/.corterm/corterm\n';
    // 两行裸调用，取第一行。
    final controller = WorkerProcessController(daemonLister: () async => ps);
    expect(await controller.findDaemonPid(), 456);

    final none = WorkerProcessController(
      daemonLister: () async =>
          '  789 /Users/x/.corterm/corterm status --json\n'
          '  222 /usr/sbin/corterm-helper\n',
    );
    expect(await none.findDaemonPid(), isNull);
  });

  test('killed daemon is respawned with backoff', () async {
    if (!Platform.isMacOS) return;
    final home = _tempHome();
    final daemon = _daemonScript(home);
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async => '',
      binaryPathResolver: () async => BinaryPaths(corterm: daemon.path),
    );
    addTearDown(controller.stop);

    await controller.start();
    final first = await _waitForLog(home, 'spawned pid');
    final firstPid = RegExp(r'spawned pid (\d+)').firstMatch(first)!.group(1)!;

    // 模拟崩溃：外部 SIGKILL → 1s 退避后应重拉。
    Process.killPid(int.parse(firstPid), ProcessSignal.sigkill);
    final log =
        await _waitForLog(home, RegExp('spawned pid (?!$firstPid)'));
    expect(RegExp('spawned pid').allMatches(log).length, 2);
  });

  test('stop prevents respawn and kills the child', () async {
    if (!Platform.isMacOS) return;
    final home = _tempHome();
    final daemon = _daemonScript(home);
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async => '',
      binaryPathResolver: () async => BinaryPaths(corterm: daemon.path),
    );

    await controller.start();
    await _waitForLog(home, 'spawned pid');
    await controller.stop();

    await Future<void>.delayed(const Duration(seconds: 3));
    expect(RegExp('spawned pid').allMatches(_readLog(home)).length, 1);
  });

  test('adopted daemon is not respawned but is killed on stop', () async {
    if (!Platform.isMacOS) return;
    final home = _tempHome();
    final daemon = _daemonScript(home);
    // 外部先拉一个「孤儿」守护进程，lister 如实上报它的 pid。
    final orphan = await Process.start(daemon.path, []);
    addTearDown(orphan.kill);
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async =>
          '${orphan.pid} ${daemon.path}\n',
      binaryPathResolver: () async => BinaryPaths(corterm: daemon.path),
    );

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(_readLog(home), isNot(contains('spawned pid')));

    // stop 应杀掉采纳的孤儿：fake daemon 收到 TERM 会优雅退出（exit 0），
    // 断言的关键是它在超时内退出（timeout 抛异常即失败）。
    await controller.stop();
    await orphan.exitCode.timeout(const Duration(seconds: 5));
  });

  test('legacy LaunchAgent is unloaded, removed and plist deleted', () async {
    if (!Platform.isMacOS) return;
    final home = _tempHome();
    final daemon = _daemonScript(home);
    final plist = File('${home.path}/Library/LaunchAgents/com.corterm.worker.plist');
    plist.parent.createSync(recursive: true);
    plist.writeAsStringSync('<plist/>');
    final launchctlCalls = <List<String>>[];
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async => '',
      binaryPathResolver: () async => BinaryPaths(corterm: daemon.path),
      processRunner: (exe, args) async {
        launchctlCalls.add(args);
        return ProcessResult(0, 0, '', '');
      },
    );
    addTearDown(controller.stop);

    await controller.start();

    expect(plist.existsSync(), isFalse);
    expect(launchctlCalls,
        containsAll([['unload', plist.path], ['remove', 'com.corterm.worker']]));
    await _waitForLog(home, 'spawned pid');
  });

  test('undeletable plist aborts spawn to avoid double-hosting', () async {
    if (!Platform.isMacOS) return;
    final home = _tempHome();
    final daemon = _daemonScript(home);
    final agentsDir = Directory('${home.path}/Library/LaunchAgents');
    agentsDir.createSync(recursive: true);
    File('${agentsDir.path}/com.corterm.worker.plist').writeAsStringSync('<plist/>');
    Process.runSync('chmod', ['555', agentsDir.path]);
    addTearDown(() => Process.runSync('chmod', ['755', agentsDir.path]));
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async => '',
      binaryPathResolver: () async => BinaryPaths(corterm: daemon.path),
    );

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // 删不掉 plist 就不 spawn（launchd KeepAlive 会双实例）；诊断只进控制台。
    expect(_readLog(home), isNot(contains('spawned pid')));
  });

  test('spawn is skipped when binary cannot be resolved', () async {
    if (!Platform.isMacOS) return;
    final home = _tempHome();
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async => '',
      binaryPathResolver: () async => null,
    );
    addTearDown(controller.stop);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // 解析不到二进制只记诊断日志（控制台），不写 spawn 头。
    expect(_readLog(home), isNot(contains('spawned pid')));
  });

  test('adopted daemon that dies is respawned by polling', () async {
    if (!Platform.isMacOS) return;
    final home = _tempHome();
    final daemon = _daemonScript(home);
    final orphan = await Process.start(daemon.path, []);
    addTearDown(orphan.kill);
    var listedPid = orphan.pid;
    final controller = WorkerProcessController(
      homeDirOverride: home.path,
      daemonLister: () async => '$listedPid ${daemon.path}\n',
      binaryPathResolver: () async => BinaryPaths(corterm: daemon.path),
      adoptPollInterval: const Duration(milliseconds: 200),
    );
    addTearDown(controller.stop);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(_readLog(home), isNot(contains('spawned pid'))); // 先采纳

    // 孤儿被外部杀死 → 轮询发现 → 补拉（"补拉"诊断走控制台；文件里看到新 spawn 即成立）。
    orphan.kill();
    await _waitForLog(home, 'spawned pid', timeout: const Duration(seconds: 5));
  });

  test('supportsNoServiceRestart probes update --help and caches', () async {
    if (Platform.isWindows) return; // fake script uses /bin/sh
    final dir = Directory.systemTemp.createTempSync('wpc-probe');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = File('${dir.path}/count');
    final script = File('${dir.path}/fake-corterm')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'echo 1 >> ${marker.path}\n'
        'echo "  no-service-restart    Skip restarting" \n',
      );
    await Process.run('chmod', ['+x', script.path]);

    expect(await supportsNoServiceRestart(script.path), isTrue);
    expect(await supportsNoServiceRestart(script.path), isTrue);
    expect(marker.readAsStringSync().trim().split('\n').length, 1); // 缓存命中
  });

  test('update passes --no-service-restart only when asked', () async {
    if (Platform.isWindows) return;
    final dir = Directory.systemTemp.createTempSync('wpc-update');
    addTearDown(() => dir.deleteSync(recursive: true));
    final argsFile = File('${dir.path}/args');
    final script = File('${dir.path}/fake-corterm')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'echo "\$@" > ${argsFile.path}\n'
        'echo \'{"stage":"done","version":"0.5.24"}\'\n',
      );
    await Process.run('chmod', ['+x', script.path]);
    final svc = CortermService(cortermPath: script.path);

    final stages = await svc.update(noServiceRestart: true).toList();
    expect(stages.single.stage, 'done');
    expect(argsFile.readAsStringSync(), contains('--no-service-restart'));

    await svc.update().toList();
    expect(argsFile.readAsStringSync(), isNot(contains('--no-service-restart')));
  });
}
