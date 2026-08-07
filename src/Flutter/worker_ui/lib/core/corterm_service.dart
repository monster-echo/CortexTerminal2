import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// 封装对 corterm/cortap 的进程调用。全部走 `--json`，解析 stdout。
/// 失败即抛 [CortermException]，由 UI 层展示错误 banner —— 不吞错误。
class CortermService {
  CortermService({required this.cortermPath, required this.cortapPath});

  final String cortermPath;
  final String cortapPath;

  Future<Status> status() async {
    final r = await _run(cortermPath, ['status', '--json']);
    return Status.fromJson(_decodeMap(r));
  }

  Future<DoctorResult> doctor() async {
    // doctor 失败时 exit code=1 但 stdout 仍是 JSON（failedCount>0），照常解析。
    final r = await _run(cortermPath, ['doctor', '--json']);
    return DoctorResult.fromJson(_decodeMap(r));
  }

  Future<UpdateCheck> updateCheck() async {
    final r = await _run(cortermPath, ['update', '--check', '--json']);
    return UpdateCheck.fromJson(_decodeMap(r));
  }

  /// 流式更新阶段（check → download → extract → install → restart → done / error）。
  Stream<UpdateProgress> update() {
    return _runStream(
      cortermPath,
      ['update', '--json'],
      UpdateProgress.fromJson,
      (s) => s.isError,
    );
  }

  /// 流式设备码登录阶段（code → success / error）。
  Stream<LoginStageData> login() {
    return _runStream(
      cortermPath,
      ['login', '--json'],
      LoginStageData.fromJson,
      (s) => s.isError,
    );
  }

  Future<ServiceResult> service(String action) async {
    final r = await _run(cortermPath, [action, '--json']);
    return ServiceResult.fromJson(_decodeMap(r));
  }

  Future<ServiceResult> logout() async {
    final r = await _run(cortermPath, ['logout', '--json']);
    return ServiceResult.fromJson(_decodeMap(r));
  }

  Future<List<SessionSummary>> sessions() async {
    final r = await _run(cortapPath, ['sessions', '--json']);
    final decoded = _decode(r.stdout);
    if (decoded is! List) {
      throw CortermException('cortap sessions --json 返回了非数组：${r.stdout}');
    }
    return decoded
        .whereType<Map>()
        .map((m) => SessionSummary.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<CortermEvent>> events(String sessionId, {int? last}) async {
    final args = ['events', '--session', sessionId, '--json'];
    if (last != null) args.addAll(['--last', '$last']);
    final r = await _run(cortapPath, args);
    final lines = r.stdout.split('\n').where((l) => l.trim().isNotEmpty);
    return lines.map(CortermEvent.fromLine).toList();
  }

  // ── 内部实现 ──

  Future<_RunResult> _run(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      return _RunResult(
        result.stdout as String? ?? '',
        result.stderr as String? ?? '',
        result.exitCode,
      );
    } on ProcessException catch (e) {
      throw CortermException('无法启动 $executable：${e.message}');
    }
  }

  Stream<T> _runStream<T>(
    String executable,
    List<String> args,
    T Function(Map<String, dynamic>) fromJson,
    bool Function(T) isError,
  ) async* {
    late final Process proc;
    try {
      proc = await Process.start(executable, args);
    } on ProcessException catch (e) {
      throw CortermException('无法启动 $executable：${e.message}');
    }

    var sawError = false;
    final lines = proc.stdout.transform(utf8.decoder).transform(const LineSplitter());
    try {
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final decoded = _decode(line);
        if (decoded is! Map) continue; // stdout 理论上全为 JSON，防御跳过
        final item = fromJson(Map<String, dynamic>.from(decoded));
        if (isError(item)) sawError = true;
        yield item;
      }
    } finally {
      proc.kill();
    }

    final exit = await proc.exitCode;
    if (exit != 0 && !sawError) {
      final stderr = await proc.stderr.transform(utf8.decoder).join();
      throw CortermException('$executable ${args.join(' ')} 退出码 $exit\nstderr: $stderr');
    }
  }

  Map<String, dynamic> _decodeMap(_RunResult r) {
    final decoded = _decode(r.stdout);
    if (decoded is! Map) {
      throw CortermException(
        '无法解析 JSON 输出（exit=${r.exitCode}）\nstdout: ${r.stdout}\nstderr: ${r.stderr}',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      throw CortermException('stdout 不是合法 JSON：$raw');
    }
  }
}

class _RunResult {
  const _RunResult(this.stdout, this.stderr, this.exitCode);

  final String stdout;
  final String stderr;
  final int exitCode;
}

class CortermException implements Exception {
  CortermException(this.message);

  final String message;

  @override
  String toString() => message;
}
