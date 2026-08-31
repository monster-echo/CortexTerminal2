import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:worker_ui/core/binary_locator.dart';

void main() {
  test('resolveBinaryPaths resolves to an existing corterm', () async {
    // 本机有 corterm（~/.corterm 或 PATH 兜底）时返回的路径必须真实存在。
    final paths = await resolveBinaryPaths();
    expect(paths, isNotNull);
    if (paths == null) return;
    expect(File(paths.corterm).existsSync(), isTrue);
    final cortapName = Platform.isWindows ? 'cortap.exe' : 'cortap';
    expect(paths.cortap, endsWith(cortapName));
  });

  test('resolveBinaryPaths does not throw when nothing found', () async {
    // 极端情况下返回 null 而不是抛异常。
    // （本机 ~/.corterm 存在时不会走到 null 分支，这里只保证不崩）
    final paths = await resolveBinaryPaths();
    expect(paths, isA<BinaryPaths?>());
  });

  test('homeDirOf uses USERPROFILE on Windows, HOME elsewhere', () {
    // Windows 没有 HOME —— 曾经的 bug： locator 只读 HOME 导致 Windows 上
    // 既不装内置 worker 也找不到 ~/.corterm，兜底撞上 PATH 里的旧版 corterm。
    expect(
      homeDirOf({'USERPROFILE': r'C:\Users\u', 'HOME': '/ignored'}, isWindows: true),
      r'C:\Users\u',
    );
    expect(homeDirOf({'HOME': '/Users/x'}, isWindows: false), '/Users/x');
    expect(homeDirOf(const {}, isWindows: true), isNull);
    expect(homeDirOf(const {}, isWindows: false), isNull);
    expect(homeDirOf({'USERPROFILE': ''}, isWindows: true), isNull);
  });

  test('bundledAssetPathFor resolves the data/flutter_assets shape on Windows/Linux', () {
    // Windows/Linux 的 flutter assets 在可执行文件旁的 data/flutter_assets/ 下。
    final dir = Directory.systemTemp.createTempSync('bundled_asset_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final asset = File(p.join(dir.path, 'data', 'flutter_assets', 'assets', 'bin', 'corterm.exe'))
      ..createSync(recursive: true);

    final resolved = bundledAssetPathFor('corterm.exe',
        exePath: p.join(dir.path, 'worker_ui.exe'), isMacOS: false);
    expect(resolved, asset.path);
  });

  test('bundledAssetPathFor resolves the .app shapes on macOS', () {
    final dir = Directory.systemTemp.createTempSync('bundled_asset_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final asset = File(
      '${dir.path}/Contents/Resources/flutter_assets/assets/bin/corterm',
    )..createSync(recursive: true);

    final resolved = bundledAssetPathFor('corterm',
        exePath: '${dir.path}/Contents/MacOS/worker_ui', isMacOS: true);
    expect(resolved, asset.path);
  });

  test('jsonOptionPattern matches only the json option line in --help output', () {
    // System.CommandLine 2.0.7 的 help 只显示选项首别名（裸 `json`），不带 `--`。
    final withJson = 'Options:\n'
        '  json            Emit machine-readable JSON to stdout\n'
        '  -?, -h, --help  Show help and usage information';
    final withoutJson = 'Options:\n'
        '  -?, -h, --help  Show help and usage information';
    expect(jsonOptionPattern.hasMatch(withJson), isTrue);
    expect(jsonOptionPattern.hasMatch(withoutJson), isFalse);
    // 描述文字里出现 json 一词不算（行首锚定）。
    expect(jsonOptionPattern.hasMatch('  Show JSON usage'), isFalse);
  });

  test('ensureWorkerInstalled repairs an old worker that lacks --json', () async {
    // Windows 报「stdout 不是合法 JSON」的根因场景：~/.corterm 里是旧版 worker
    // （help 无 json 选项），App 内置新版 → 必须用内置的把旧版修掉。
    if (Platform.isWindows) return; // fake scripts use /bin/sh
    final (home, app) = _fixtureOldWorkerAndBundled();
    addTearDown(() {
      home.deleteSync(recursive: true);
      app.deleteSync(recursive: true);
    });

    await ensureWorkerInstalledFrom(
      homeDir: home.path,
      exePath: p.join(app.path, 'worker_ui'),
      isWindows: false,
      isMacOS: false,
    );

    final installed = File(p.join(home.path, '.corterm', 'corterm'));
    final bundled = File(p.join(app.path, 'data', 'flutter_assets', 'assets', 'bin', 'corterm'));
    expect(installed.readAsStringSync(), bundled.readAsStringSync());
  });

  test('ensureWorkerInstalled keeps a worker that already speaks --json', () async {
    if (Platform.isWindows) return; // fake scripts use /bin/sh
    final (home, app) = _fixtureOldWorkerAndBundled(newAlreadyInstalled: true);
    addTearDown(() {
      home.deleteSync(recursive: true);
      app.deleteSync(recursive: true);
    });

    await ensureWorkerInstalledFrom(
      homeDir: home.path,
      exePath: p.join(app.path, 'worker_ui'),
      isWindows: false,
      isMacOS: false,
    );

    final installed = File(p.join(home.path, '.corterm', 'corterm'));
    expect(installed.readAsStringSync(), contains('0.5.16'));
  });
}

/// 造一对「home（含已装 worker）+ App（含内置 worker）」的临时目录。
/// [newAlreadyInstalled] 为 true 时已装的就是新版（help 带 json），否则是旧版。
(Directory, Directory) _fixtureOldWorkerAndBundled({bool newAlreadyInstalled = false}) {
  final home = Directory.systemTemp.createTempSync('corterm-home');
  final app = Directory.systemTemp.createTempSync('corterm-app');

  final oldHelp = '#!/bin/sh\n'
      'echo "Options:\\n  -?, -h, --help  Show help and usage information"\n'
      'exit 0\n';
  final newHelp = '#!/bin/sh\n'
      'echo "# 0.5.16"\n'
      'echo "Options:\\n  json            Emit machine-readable JSON to stdout\\n'
      '  -?, -h, --help  Show help and usage information"\n'
      'exit 0\n';

  final installed = File(p.join(home.path, '.corterm', 'corterm'))
    ..createSync(recursive: true)
    ..writeAsStringSync(newAlreadyInstalled ? newHelp : oldHelp);
  Process.runSync('chmod', ['+x', installed.path]);

  File(p.join(app.path, 'data', 'flutter_assets', 'assets', 'bin', 'corterm'))
    ..createSync(recursive: true)
    ..writeAsStringSync(newHelp);

  return (home, app);
}
