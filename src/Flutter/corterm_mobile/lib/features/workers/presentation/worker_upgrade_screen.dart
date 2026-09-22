import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../sessions/data/session_repository.dart';

/// Worker 升级进度页（对齐用户诉求：独立页面展示进度，可返回、可再进查看）。
///
/// 网关升级是"下发指令 + Worker 自更新"的异步过程，无进度端点——
/// 通过轮询 workerDetail 观察三个阶段：指令下发 → 离线（下载/重启中）→
/// 上线且版本达标（完成）。超时（3 分钟）给出可返回的降级提示。
class WorkerUpgradeScreen extends ConsumerStatefulWidget {
  const WorkerUpgradeScreen({
    super.key,
    required this.workerId,
    required this.name,
  });

  final String workerId;
  final String name;

  @override
  ConsumerState<WorkerUpgradeScreen> createState() =>
      _WorkerUpgradeScreenState();
}

enum _UpgradePhase { dispatching, updating, verifying, done, failed, timeout }

class _WorkerUpgradeScreenState extends ConsumerState<WorkerUpgradeScreen> {
  _UpgradePhase _phase = _UpgradePhase.dispatching;
  String? _error;
  String? _fromVersion;
  String? _targetVersion;
  Timer? _pollTimer;
  int _elapsed = 0;
  static const _timeoutSeconds = 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _dispatch());
  }

  Future<void> _dispatch() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final worker = (await ref.read(sessionRepositoryProvider).workerDetail(widget.workerId)).worker;
      _fromVersion ??= worker.version;
      final result =
          await ref.read(sessionRepositoryProvider).upgradeWorker(widget.workerId);
      if (!mounted) return;
      setState(() {
        _targetVersion = result.targetVersion ?? _targetVersion;
        _fromVersion ??= worker.version;
        _phase = _UpgradePhase.updating;
      });
      _startPolling(l10n);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpgradePhase.failed;
        _error = '${l10n.upgradeDispatchFailed}: $e';
      });
    }
  }

  void _startPolling(AppLocalizations l10n) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      _elapsed += 3;
      if (_elapsed >= _timeoutSeconds) {
        timer.cancel();
        if (mounted) setState(() => _phase = _UpgradePhase.timeout);
        return;
      }
      try {
        final detail =
            await ref.read(sessionRepositoryProvider).workerDetail(widget.workerId);
        final w = detail.worker;
        if (!mounted) return;
        setState(() {
          _targetVersion ??= w.version;
          // 离线 = 正在下载/重启；上线且版本达标 = 完成。
          if (!w.isOnline) {
            _phase = _UpgradePhase.verifying;
          } else if (_targetReached(w.version)) {
            _phase = _UpgradePhase.done;
            timer.cancel();
          } else {
            _phase = _UpgradePhase.verifying;
          }
        });
      } catch (_) {
        // 轮询偶发失败不中断升级观察，等下一轮。
      }
    });
  }

  bool _targetReached(String? version) {
    final target = _targetVersion;
    if (target == null || version == null) return false;
    return _normalize(version) == _normalize(target);
  }

  /// 版本尾段 .0 归一（对齐网关 NormalizeVersion："0.4.0.0" → "0.4"）。
  String _normalize(String v) {
    final parts = v.split('.');
    while (parts.length > 1 && parts.last == '0') {
      parts.removeLast();
    }
    return parts.join('.');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    final steps = <(_UpgradePhase, IconData, String)>[
      (_UpgradePhase.dispatching, LucideIcons.send, l10n.upgradeStepDispatch),
      (_UpgradePhase.updating, LucideIcons.download, l10n.upgradeStepUpdate),
      (_UpgradePhase.verifying, LucideIcons.refreshCw, l10n.upgradeStepVerify),
    ];

    // 当前进行到哪一步（done/timeout 视为全部走完）。
    final reached = switch (_phase) {
      _UpgradePhase.dispatching => 0,
      _UpgradePhase.updating => 1,
      _UpgradePhase.verifying => 2,
      _ => 3,
    };

    Widget stepRow(int index, IconData icon, String label) {
      final state = index < reached
          ? 'done'
          : index == reached && _phase != _UpgradePhase.failed
              ? 'active'
              : 'pending';
      final color = switch (state) {
        'done' => scheme.success,
        'active' => scheme.primary,
        _ => scheme.mutedForeground,
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            switch (state) {
              'done' => Icon(LucideIcons.check, size: 18, color: color),
              'active' => const SizedBox(
                  width: 18,
                  height: 18,
                  child: ShadProgress(value: null),
                ),
              _ => Icon(LucideIcons.circle, size: 14, color: color),
            },
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: theme.textTheme.small.copyWith(color: scheme.foreground)),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        backgroundColor: scheme.background,
        foregroundColor: scheme.foreground,
        elevation: 0,
        title: Text(
          l10n.upgradePageTitle,
          style: theme.textTheme.large.copyWith(
            color: scheme.foreground,
            fontSize: 17,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  widget.name,
                  style: theme.textTheme.large.copyWith(color: scheme.foreground),
                ),
              ),
              const SizedBox(height: 24),
              // 版本迁移：当前 → 目标。
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _fromVersion ?? '—',
                    style: theme.textTheme.small.copyWith(
                      color: scheme.mutedForeground,
                      fontFamily: 'packages/shadcn_ui/GeistMono',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(LucideIcons.arrowRight,
                        size: 18, color: scheme.mutedForeground),
                  ),
                  Text(
                    _targetVersion ?? '…',
                    style: theme.textTheme.small.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'packages/shadcn_ui/GeistMono',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (_phase == _UpgradePhase.failed)
                ShadAlert.destructive(
                  icon: const Icon(LucideIcons.circleAlert),
                  title: Text(l10n.upgradeDispatchFailed),
                  description: Text(_error ?? ''),
                )
              else if (_phase == _UpgradePhase.timeout)
                ShadAlert(
                  icon: const Icon(LucideIcons.clockAlert),
                  title: Text(l10n.upgradeTimeout),
                  description: Text(l10n.lastActivity),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.border),
                  ),
                  child: Column(
                    children: [
                      for (final (i, (_, icon, label)) in steps.indexed)
                        stepRow(i, icon, label),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              if (_phase == _UpgradePhase.done)
                ShadButton(
                  onPressed: () => context.go('/workers'),
                  leading: const Icon(LucideIcons.check, size: 16),
                  child: Text(l10n.upgradeDone),
                )
              else ...[
                ShadButton.outline(
                  onPressed: () => context.pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    // 可返回；再次从 Worker 详情进入会继续观察状态。
                    l10n.upgradeStepVerify,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.muted.copyWith(
                      color: scheme.mutedForeground,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
