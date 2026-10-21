import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/binary_locator.dart';
import '../core/corterm_service.dart';
import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/self_updater.dart';
import '../core/worker_process_controller.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/primary_button.dart';
import '../widgets/states.dart';

/// 统一更新页：应用 + Worker 一个概念。一次检查、一个按钮。
/// 更新顺序：先 Worker（corterm），后 UI —— UI 更新会
/// 重启应用，必须放在最后收尾。
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _Stage {
  _Stage(this.label, {this.isError = false, this.bytes});

  final String label;
  final bool isError;
  final int? bytes;
}

class _UpdateScreenState extends State<UpdateScreen> {
  late CortermService _service;
  bool _started = false;
  UpdateCheck? _workerCheck;
  UiUpdateCheck? _uiCheck;
  String? _error;
  bool _checking = false;
  bool _updating = false;
  final List<_Stage> _stages = [];
  int? _uiDownloaded;
  int? _uiTotal;

  bool get _uiAvailable =>
      !isStoreBuild && (_uiCheck?.updateAvailable ?? false);
  bool get _workerAvailable => _workerCheck?.updateAvailable ?? false;
  bool get _anyAvailable =>
      _uiAvailable || (!isWindowsStoreBuild && _workerAvailable);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service = AppScope.of(context).service;
    if (!_started) {
      _started = true;
      _checkForUpdates();
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    // 开发构建（未注入 UI_VERSION）没有可比版本，跳过 UI 自查，
    // 只查服务版本——省一次无意义的 GitHub API 调用。
    final futures = <Future<dynamic>>[
      if (appVersion != '0.0.0' && !isStoreBuild) SelfUpdater.check(),
      if (!isWindowsStoreBuild) _service.updateCheck(),
    ];
    final labels = <String>[
      if (appVersion != '0.0.0' && !isStoreBuild) '应用',
      if (!isWindowsStoreBuild) '服务',
    ];
    try {
      final results = await Future.wait<dynamic>(futures);
      if (!mounted) return;
      setState(() {
        var i = 0;
        if (appVersion != '0.0.0' && !isStoreBuild) {
          _uiCheck = results[i] as UiUpdateCheck;
          i++;
        }
        if (!isWindowsStoreBuild) _workerCheck = results[i] as UpdateCheck;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 多源并行时无法定位失败方，标注来源让用户知道是哪条链路断了。
      setState(() {
        _error = '${labels.join('/')}版本检查失败：$e';
        _checking = false;
      });
    }
  }

  /// 一键更新：Worker 先行（CLI 流式阶段），UI 收尾（成功路径不返回）。
  Future<void> _updateAll() async {
    setState(() {
      _updating = true;
      _error = null;
      _stages.clear();
    });

    if (!isWindowsStoreBuild && _workerAvailable) {
      try {
        // macOS：worker 由本 App 托管，CLI 不做服务重启（会走 launchctl 装回
        // LaunchAgent 拉起第二实例）；旧 worker 不认识该选项，探测后再传。
        final noServiceRestart =
            Platform.isMacOS && await supportsNoServiceRestart(_service.cortermPath);
        var workerUpdated = false;
        await for (final stage in _service.update(noServiceRestart: noServiceRestart)) {
          if (!mounted) return;
          setState(() {
            _stages.add(
              _Stage(stage.stage, isError: stage.isError, bytes: stage.bytes),
            );
            if (stage.isError) _error = stage.message ?? 'update failed';
          });
          if (stage.isError) {
            setState(() => _updating = false);
            return;
          }
          if (stage.isDone) {
            workerUpdated = true;
            break;
          }
        }
        // 重启托管的 worker 子进程换上新二进制。
        if (workerUpdated && noServiceRestart) {
          setState(() => _stages.add(_Stage('restart')));
          await WorkerProcessController.instance.restart();
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _updating = false;
        });
        return;
      }
    }

    if (_uiAvailable) {
      try {
        // 成功路径不返回：安装包启动后应用直接退出。
        await SelfUpdater.apply(
          onProgress: (received, total) {
            if (!mounted) return;
            setState(() {
              _uiDownloaded = received;
              _uiTotal = total;
            });
          },
        );
        if (!mounted) return;
        setState(() {
          _stages.add(_Stage('apply'));
          _stages.add(_Stage('relaunch'));
          _updating = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _updating = false;
        });
      }
      return;
    }

    setState(() => _updating = false);
  }

  String _stageLabel(BuildContext context, String stage) {
    final t = AppStrings.t;
    switch (stage) {
      case 'check':
        return t(context, 'update.stage.check');
      case 'download':
        return t(context, 'update.stage.download');
      case 'extract':
        return t(context, 'update.stage.extract');
      case 'install':
        return t(context, 'update.stage.install');
      case 'restart':
        return t(context, 'update.stage.restart');
      case 'apply':
        return t(context, 'update.stage.apply');
      case 'relaunch':
        return t(context, 'update.stage.relaunch');
      case 'done':
        return t(context, 'update.stage.done');
      case 'error':
        return t(context, 'common.error');
      default:
        return stage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    final checked =
        _workerCheck != null || _uiCheck != null || isWindowsStoreBuild;
    // 未打版本号的本地构建（UI_VERSION 缺省 0.0.0）不参与更新比较。
    final devBuild = appVersion == '0.0.0';
    String withLatest(String current, String? latest) =>
        (latest == null || latest == current) ? current : '$current → v$latest';
    return Scaffold(
      appBar: WorkerAppBar(
        title: t(context, 'update.title'),
        actions: [
          if (!_checking && !_updating)
            ShadIconButton.ghost(
              onPressed: _checkForUpdates,
              icon: Icon(LucideIcons.refreshCw, size: 18),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_checking)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: SmallSpinner(),
                ),
              )
            else ...[
              ErrorBanner(message: _error),
              if (isWindowsStoreBuild)
                AppGroupCard(
                  children: [
                    AppRow(
                      label: t(context, 'update.uiCurrent'),
                      value: 'v$appVersion',
                    ),
                    const Divider(height: 1),
                    AppRow(
                      label: t(context, 'update.uiCurrent'),
                      value: t(context, 'update.storeManaged'),
                    ),
                  ],
                ),
              if (checked && !isWindowsStoreBuild) ...[
                // 每行「当前 → 最新」，不再单独设「最新版本」行。
                AppGroupCard(
                  children: [
                    AppRow(
                      label: t(context, 'update.uiCurrent'),
                      value: devBuild
                          ? 'v$appVersion（开发构建）'
                          : withLatest('v$appVersion', _uiCheck?.latestVersion),
                    ),
                    if (_workerCheck != null) ...[
                      const Divider(height: 1),
                      AppRow(
                        label: t(context, 'update.serviceCurrent'),
                        value: withLatest(
                          'v${_workerCheck!.currentVersion}',
                          _workerCheck!.latestVersion,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (checked && _anyAvailable && !_updating && !isStoreBuild) ...[
                const SizedBox(height: 8),
                Text(
                  t(context, 'update.allNote'),
                  style: TextStyle(color: scheme.mutedForeground, fontSize: 13),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: t(context, 'update.allTrigger'),
                  onPressed: _updateAll,
                  icon: LucideIcons.download,
                  expanded: true,
                ),
              ],
              if (checked && !_anyAvailable && !_updating && !isStoreBuild)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    t(context, 'update.upToDate'),
                    style: TextStyle(
                      color: scheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_updating) ...[
                const SizedBox(height: 16),
                ShadProgress(
                  value:
                      _uiTotal != null && _uiTotal! > 0 && _uiDownloaded != null
                      ? _uiDownloaded! / _uiTotal!
                      : null,
                  minHeight: 4,
                ),
                const SizedBox(height: 16),
                AppGroupCard(
                  children: [
                    for (var i = 0; i < _stages.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(
                        builder: (context) {
                          final s = _stages[i];
                          return AppRow(
                            icon: s.isError
                                ? LucideIcons.circleX
                                : LucideIcons.circleCheck,
                            iconColor: s.isError
                                ? scheme.destructive
                                : scheme.tertiary,
                            label: _stageLabel(context, s.label),
                            trailing: s.bytes != null && s.bytes! > 0
                                ? Text('${s.bytes} B')
                                : null,
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
