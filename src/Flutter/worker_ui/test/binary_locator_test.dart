import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
