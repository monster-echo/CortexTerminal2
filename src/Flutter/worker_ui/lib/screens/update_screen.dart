import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../core/self_updater.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_header.dart';
import '../widgets/status_card.dart';

/// 统一更新页：应用 + Worker 一个概念。一次检查、一个按钮。
/// 更新顺序：先 Worker（corterm + cortap 一体更新），后 UI —— UI 更新会
/// 重启应用，必须放在最后收尾。
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, required this.service});

  final CortermService service;

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
  UpdateCheck? _workerCheck;
  UiUpdateCheck? _uiCheck;
  String? _error;
  bool _checking = false;
  bool _updating = false;
  final List<_Stage> _stages = [];
  int? _uiDownloaded;
  int? _uiTotal;

  bool get _uiAvailable => _uiCheck?.updateAvailable ?? false;
  bool get _workerAvailable => _workerCheck?.updateAvailable ?? false;
  bool get _anyAvailable => _uiAvailable || _workerAvailable;

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        SelfUpdater.check(),
        widget.service.updateCheck(),
      ]);
      if (!mounted) return;
      setState(() {
        _uiCheck = results[0] as UiUpdateCheck;
        _workerCheck = results[1] as UpdateCheck;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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

    if (_workerAvailable) {
      try {
        await for (final stage in widget.service.update()) {
          if (!mounted) return;
          setState(() {
            _stages.add(_Stage(stage.stage, isError: stage.isError, bytes: stage.bytes));
            if (stage.isError) _error = stage.message ?? 'update failed';
          });
          if (stage.isError) {
            setState(() => _updating = false);
            return;
          }
          if (stage.isDone) break;
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
    final checked = _workerCheck != null || _uiCheck != null;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: t(context, 'update.title'),
            trailing: PrimaryButton(
              label: t(context, 'update.check'),
              onPressed: _checking || _updating ? null : _checkForUpdates,
              icon: LucideIcons.search,
            ),
          ),
          const SizedBox(height: 16),
          ErrorBanner(message: _error),
          const SizedBox(height: 16),
          StatusCard(
            title: t(context, 'update.allTitle'),
            items: [
              (t(context, 'update.uiCurrent'), 'v$appVersion'),
              if (_workerCheck != null)
                (t(context, 'update.workerCurrent'), 'v${_workerCheck!.currentVersion}'),
              if (checked) ...[
                // 本地构建可能比线上最新还新（发布前的开发版），此时「最新版本」
                // 显示为当前版本，避免「最新 < 当前」的观感。
                (
                  t(context, 'update.latest'),
                  _anyAvailable
                      ? 'v${_uiAvailable ? _uiCheck!.latestVersion : _workerCheck!.latestVersion}'
                      : 'v$appVersion'
                ),
                (t(context, 'update.available'), _anyAvailable ? '●' : '—'),
              ],
            ],
          ),
          if (checked && _anyAvailable && !_updating) ...[
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
          if (checked && !_anyAvailable && !_updating)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                t(context, 'update.upToDate'),
                style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600),
              ),
            ),
          if (_updating) ...[
            const SizedBox(height: 16),
            ShadProgress(
              value: _uiTotal != null && _uiTotal! > 0 && _uiDownloaded != null
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
                        icon: s.isError ? LucideIcons.circleX : LucideIcons.circleCheck,
                        iconColor: s.isError ? scheme.destructive : scheme.tertiary,
                        label: _stageLabel(context, s.label),
                        trailing: s.bytes != null && s.bytes! > 0 ? Text('${s.bytes} B') : null,
                      );
                    },
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
