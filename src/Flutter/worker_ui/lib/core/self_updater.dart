import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// App 自身版本，CI 构建时用 `--dart-define=UI_VERSION=x.y.z` 注入
/// （worker-ui-release.yml 的 flutter build 带）。
const appVersion = String.fromEnvironment('UI_VERSION', defaultValue: '0.0.0');

/// Microsoft Store packages are updated by the Store.
const isStoreBuild = bool.fromEnvironment('STORE_BUILD', defaultValue: false);
const isWindowsStoreBuild =
    isStoreBuild &&
    bool.fromEnvironment('WINDOWS_STORE_BUILD', defaultValue: false);

/// UI 自更新检查结果。
class UiUpdateCheck {
  const UiUpdateCheck({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.assetName,
    required this.downloadUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final String assetName;
  final String downloadUrl;
}

/// 应用（云枢终端 UI）自更新：查 GitHub `ui-v*` release → 下载平台安装包 →
/// 覆盖安装 → 重启应用。
///
/// worker（corterm）更新不在这里 —— 走 `corterm update --json`
/// （CortermService.update），一次更新同时带上两个二进制。
class SelfUpdater {
  SelfUpdater._();

  static const _repo = 'monster-echo/CortexTerminal2';
  static const _tagPrefix = 'ui-v';

  static String get _githubProxy =>
      Platform.environment['CORTERM_GITHUB_PROXY'] ?? '';

  /// 与 worker release 对齐的固定资产名（`releases/latest/download/<资产名>` 可直达）。
  static String get _assetName {
    if (Platform.isMacOS) return 'corterm-ui-macos.dmg';
    if (Platform.isWindows) return 'corterm-ui-windows-setup.exe';
    throw UnsupportedError('UI 自更新不支持平台：${Platform.operatingSystem}');
  }

  static HttpClient _client() {
    final c = HttpClient()..autoUncompress = true;
    c.userAgent = 'Corterm-UI/$appVersion';
    return c;
  }

  /// 查最新 `ui-v*` release。多个 release 里取最高 semver（对齐 C# 侧：
  /// GitHub /releases 列表不保证按版本排序）。
  static Future<UiUpdateCheck> check() async {
    if (isStoreBuild) throw UnsupportedError('商店版本由 Microsoft Store 管理更新');
    final assetName = _assetName;
    final latest = await _latestVersion();
    final url =
        'https://github.com/$_repo/releases/download/$_tagPrefix$latest/$assetName';
    return UiUpdateCheck(
      currentVersion: appVersion,
      latestVersion: latest,
      updateAvailable: versionCompare(latest, appVersion) > 0,
      assetName: assetName,
      downloadUrl: url,
    );
  }

  static Future<String> _latestVersion() async {
    // 不用代理查版本：proxy.0x2a.top 只放行 release 下载路径（HTML/API 均 403）。
    // 1) 直连 github.com /releases/latest：302 Location 带版本号，不占 API 配额；
    // 2) 回退直连 api.github.com /releases（配额未超时可用）。
    try {
      return await _latestViaRedirect();
    } catch (_) {
      return _latestViaApi();
    }
  }

  static Future<String> _latestViaRedirect() async {
    var current = Uri.parse('https://github.com/$_repo/releases/latest');
    final client = _client();
    for (var hop = 0; hop < 5; hop++) {
      final req = await client.getUrl(current)
        ..followRedirects = false
        ..maxRedirects = 0;
      final resp = await req.close();
      if (resp.isRedirect) {
        final location = resp.headers.value('location');
        if (location == null) break;
        current = current.resolve(location);
        continue;
      }
      final body = await resp.transform(utf8.decoder).join();
      final tag = _tagFromText(current.toString()) ?? _tagFromText(body);
      if (tag == null) {
        throw HttpException('未在响应中找到 $_tagPrefix*：${resp.statusCode}');
      }
      return tag;
    }
    throw StateError('重定向次数过多');
  }

  static Future<String> _latestViaApi() async {
    final req = await _client().getUrl(
      Uri.parse('https://api.github.com/repos/$_repo/releases'),
    );
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw HttpException(
        '获取 releases 失败：${resp.statusCode}（匿名配额 60 次/h/IP 可能已超）',
      );
    }
    final releases = jsonDecode(body) as List;
    String? best;
    Version? bestParsed;
    for (final item in releases) {
      final tag = (item as Map)['tag_name'] as String? ?? '';
      if (!tag.startsWith(_tagPrefix)) continue;
      final ver = tag.substring(_tagPrefix.length);
      final Version parsed;
      try {
        parsed = Version.parse(ver);
      } on FormatException {
        continue;
      }
      if (bestParsed == null || bestParsed.compareTo(parsed) < 0) {
        bestParsed = parsed;
        best = ver;
      }
    }
    if (best == null) throw StateError('未找到 $_tagPrefix* 格式的 release');
    return best;
  }

  /// 从 URL 或 HTML 文本里抓最高语义的 `ui-v<semver>`（首个匹配即可：
  /// redirect Location 与 tag 页标题都只含目标版本）。
  static String? _tagFromText(String text) {
    final m = RegExp(
      RegExp.escape(_tagPrefix) + r'(\d+(?:\.\d+)+)',
    ).firstMatch(text);
    return m?.group(1);
  }

  /// 下载并应用更新。成功路径**不返回**：安装包启动后直接 exit(0)。
  /// [onProgress] 收到 (已接收字节, 总字节|null)。
  static Future<void> apply({
    void Function(int received, int? total)? onProgress,
  }) async {
    if (isStoreBuild) throw UnsupportedError('商店版本由 Microsoft Store 管理更新');
    final latest = await check();
    if (!latest.updateAvailable) {
      throw StateError('已是最新版本（v${latest.currentVersion}），无需更新');
    }
    final file = await _download(latest.downloadUrl, onProgress);
    if (Platform.isMacOS) {
      await _applyMacos(file);
    } else {
      await _applyWindows(file);
    }
  }

  static Future<File> _download(
    String url,
    void Function(int, int?)? onProgress,
  ) async {
    try {
      return await _downloadFrom(url, onProgress);
    } catch (_) {
      if (_githubProxy.isEmpty) rethrow;
      return _downloadFrom(
        '${_githubProxy.replaceFirst(RegExp(r'/$'), '')}/$url',
        onProgress,
      );
    }
  }

  static Future<File> _downloadFrom(
    String url,
    void Function(int, int?)? onProgress,
  ) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw HttpException('下载失败：${resp.statusCode}', uri: Uri.parse(url));
      }
      final tmp = p.join(Directory.systemTemp.path, _assetName);
      final sink = File(tmp).openWrite();
      var received = 0;
      final total = resp.contentLength > 0 ? resp.contentLength : null;
      try {
        await for (final chunk in resp) {
          received += chunk.length;
          onProgress?.call(received, total);
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return File(tmp);
    } finally {
      client.close(force: true);
    }
  }

  /// macOS：挂载 DMG → `ditto` 覆盖当前 .app → 卸载 → `open` 重启。
  static Future<void> _applyMacos(File dmg) async {
    final mnt = p.join(Directory.systemTemp.path, 'corterm-ui-update');
    // 上次更新中途崩溃留下的挂载点先卸掉（正常情况下不存在）。
    if (Directory(mnt).existsSync()) {
      await _run('hdiutil', ['detach', mnt, '-force']);
    }
    await _run('hdiutil', [
      'attach',
      dmg.path,
      '-nobrowse',
      '-readonly',
      '-mountpoint',
      mnt,
    ]);
    try {
      final entries = Directory(mnt).listSync();
      final app =
          entries.firstWhere(
                (e) => e is Directory && e.path.endsWith('.app'),
                orElse: () => throw StateError(
                  'DMG 内没有 .app：${entries.map((e) => e.path)}',
                ),
              )
              as Directory;

      // ditto 保留权限/元数据，覆盖运行中的 .app 是安全且推荐的方式。
      await _run('ditto', [app.path, _macosAppBundle()]);
    } finally {
      await _run('hdiutil', ['detach', mnt, '-force']);
    }
    await _run('open', [_macosAppBundle()]);
    exit(0);
  }

  /// 当前 .app 包路径：<...>/Corterm.app/Contents/MacOS/Corterm → 上两级。
  static String _macosAppBundle() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.normalize(p.join(exeDir, '..', '..'));
  }

  /// Windows：Inno Setup 静默覆盖安装（/CLOSEAPPLICATIONS 等待本进程退出后替换
  /// exe）。安装完成后由 [Run] 段重新拉起应用。
  static Future<void> _applyWindows(File setupExe) async {
    final proc = await Process.start(setupExe.path, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
    ]);
    // 安装器已启动；等它读到启动状态即可退出，释放 Corterm.exe 的镜像锁。
    await proc.stdout.drain<void>();
    exit(0);
  }

  static Future<void> _run(String executable, List<String> args) async {
    final r = await Process.run(executable, args);
    if (r.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${r.stderr}'.trim().isEmpty
            ? '$executable 退出码 ${r.exitCode}'
            : '${r.stderr}'.trim(),
        r.exitCode,
      );
    }
  }
}

/// 点分数字版本比较（"0.1.0" vs "0.2.1"）。段数不齐时短的补 0；
/// 非 `数字[.数字]*` 抛 [FormatException]（对齐 C# 侧 Version.TryParse 跳过的行为）。
int versionCompare(String a, String b) {
  return Version.parse(a).compareTo(Version.parse(b));
}

class Version implements Comparable<Version> {
  Version(this.parts);

  final List<int> parts;

  factory Version.parse(String s) {
    final segs = s.split('.');
    if (segs.isEmpty || segs.any((e) => e.isEmpty || int.tryParse(e) == null)) {
      throw FormatException('非法版本号：$s');
    }
    return Version(segs.map(int.parse).toList());
  }

  @override
  int compareTo(Version other) {
    final n = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < n; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }
}
