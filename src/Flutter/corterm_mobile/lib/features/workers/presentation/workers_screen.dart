import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../app/theme/app_theme.dart';

import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/install_prompt.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/connection_status_dot.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../sessions/data/session_repository.dart';
import '../../workspace/widgets/session_status.dart';

/// Workers（阶段4）：列表 + 详情（含宿主会话）+ 升级。
class WorkersScreen extends ConsumerWidget {
  const WorkersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final workers = ref.watch(workersProvider);

    return AppShellScaffold(
      tab: ShellTab.workers,
      title: l10n.workersTitle,
      body: workers.when(
        loading: () => const SmallSpinner(),
        error: (e, _) => ErrorState(message: '$e', onRetry: () => ref.invalidate(workersProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(workersProvider);
            await ref.read(workersProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if (list.isEmpty)
                _EmptyWorkersCard(l10n: l10n),
              for (final w in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => _showDetail(context, ref, w.workerId),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      // 离线 worker 整行降透明度，一眼区分在线/离线。
                      child: Opacity(
                        opacity: w.isOnline ? 1.0 : 0.55,
                        child: ShadCard(
                          width: double.infinity,
                          title: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: workerDotColor(scheme, w),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  w.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.small.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.foreground,
                                  ),
                                ),
                              ),
                              if (w.sessionCount > 0) ...[
                                const SizedBox(width: 8),
                                Text(
                                  l10n.sessionCount(w.sessionCount),
                                  style: ShadTheme.of(context)
                                      .textTheme
                                      .muted
                                      .copyWith(color: scheme.mutedForeground),
                                ),
                              ],
                            ],
                          ),
                          description: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  [
                                    if (w.isOnline) l10n.connLive else l10n.workerOffline,
                                    if (w.hostname?.isNotEmpty ?? false) w.hostname!,
                                    [w.operatingSystem, w.architecture]
                                        .whereType<String>()
                                        .where((s) => s.isNotEmpty)
                                        .join(' '),
                                    if (w.version?.isNotEmpty ?? false) 'v${w.version}',
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // 行内资源微可视化：打开详情前就能感知负载。
                              if (w.isOnline &&
                                  (w.cpuUsagePercent != null || w.memoryUsagePercent != null)) ...[
                                const SizedBox(width: 10),
                                _MiniResourceBars(
                                  cpu: w.cpuUsagePercent,
                                  memory: w.memoryUsagePercent,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, WidgetRef ref, String workerId) async {
    final repo = ref.read(sessionRepositoryProvider);
    final l10n = AppLocalizations.of(context)!;
    WorkerDetail detail;
    try {
      detail = await repo.workerDetail(workerId);
    } catch (e) {
      if (!context.mounted) return;
      showAppToast(context, '$e', destructive: true);
      return;
    }
    if (!context.mounted) return;
    await showCortermSheet(
      context: context,
      builder: (context) => _WorkerDetailSheet(initialDetail: detail, l10n: l10n),
    );
  }
}

/// 空态：说明 + 安装引导合并为一张叙事完整的卡片。
class _EmptyWorkersCard extends StatelessWidget {
  const _EmptyWorkersCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        color: scheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.server, size: 32, color: scheme.mutedForeground),
          const SizedBox(height: 12),
          Text(
            l10n.noWorkers,
            textAlign: TextAlign.center,
            style: ShadTheme.of(context)
                .textTheme
                .p
                .copyWith(fontWeight: FontWeight.w600, color: scheme.foreground),
          ),
          const SizedBox(height: 16),
          InstallPromptCard(
            title: l10n.installWorkerTitle,
            intro: l10n.installWorkerIntro,
          ),
        ],
      ),
    );
  }
}

/// 行内资源微可视化：CPU / 内存两根 3px 细条，无数据的维度不画。
class _MiniResourceBars extends StatelessWidget {
  const _MiniResourceBars({this.cpu, this.memory});

  final double? cpu;
  final double? memory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniBar(percent: cpu),
          const SizedBox(height: 3),
          _MiniBar(percent: memory),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.percent});

  final double? percent;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final p = percent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(1.5),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            ColoredBox(
              color: scheme.secondary.withValues(alpha: 0.18),
              child: const SizedBox.expand(),
            ),
            if (p != null)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (p / 100).clamp(0.0, 1.0),
                child: ColoredBox(color: loadColor(scheme, p)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 负载阈值配色：>85% 红、>60% 黄、其余绿、无数据灰。
Color loadColor(ShadColorScheme scheme, double? p) {
  if (p == null) return scheme.mutedForeground;
  if (p > 85) return scheme.destructive;
  if (p > 60) return scheme.warning;
  return scheme.success;
}

/// Worker 详情 sheet：每 5s 轮询刷新资源统计，刷新失败在面板内展示错误。
class _WorkerDetailSheet extends ConsumerStatefulWidget {
  const _WorkerDetailSheet({required this.initialDetail, required this.l10n});

  final WorkerDetail initialDetail;
  final AppLocalizations l10n;

  @override
  ConsumerState<_WorkerDetailSheet> createState() => _WorkerDetailSheetState();
}

class _WorkerDetailSheetState extends ConsumerState<_WorkerDetailSheet> {
  late WorkerDetail detail = widget.initialDetail;
  Object? refreshError;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = ref.read(sessionRepositoryProvider);
    try {
      final d = await repo.workerDetail(detail.worker.workerId);
      if (!mounted) return;
      setState(() {
        detail = d;
        refreshError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => refreshError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final l10n = widget.l10n;
    final w = detail.worker;
    final rows = <(String, String, String)>[
      (l10n.workerHostname, w.hostname ?? '—', ''),
      (l10n.workerOs, [w.operatingSystem, w.architecture].whereType<String>().join(' '), ''),
      (
        l10n.workerVersion,
        w.version ?? '—',
        'mono',
      ),
      (
        l10n.lastActivity,
        w.lastSeenAtUtc != null ? _fmtRelative(w.lastSeenAtUtc!, l10n) : '—',
        '',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ConnectionStatusDot(
                  color: workerDotColor(scheme, w),
                  size: 10,
                  pulse: w.isOnline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    w.displayName,
                    style: ShadTheme.of(context)
                        .textTheme
                        .large
                        .copyWith(color: scheme.foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ShadButton.ghost(
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context: context,
                      title: l10n.upgradeConfirmTitle(w.displayName),
                      body: l10n.upgradeConfirmBody,
                      confirmLabel: l10n.upgrade,
                      destructive: false,
                    );
                    if (!confirmed || !context.mounted) return;
                    context.push(
                      '/workers/${w.workerId}/upgrade'
                      '?name=${Uri.encodeComponent(w.displayName)}',
                    );
                  },
                  child: Text(l10n.upgrade),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 资源占用（实时统计，5s 轮询）。
            _ResourceBar(
              label: l10n.workerCpu,
              percent: w.cpuUsagePercent,
            ),
            const SizedBox(height: 10),
            _ResourceBar(
              label: l10n.workerMemory,
              percent: w.memoryUsagePercent,
            ),
            const SizedBox(height: 12),
            if (refreshError != null) ...[
              Row(
                children: [
                  Icon(LucideIcons.circleAlert, size: 15, color: scheme.destructive),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$refreshError',
                      style: theme.textTheme.small.copyWith(color: scheme.destructive),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        row.$1,
                        style: ShadTheme.of(context)
                            .textTheme
                            .muted
                            .copyWith(color: scheme.mutedForeground),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: row.$3 == 'mono'
                            ? ShadTheme.of(context).textTheme.small.copyWith(
                                  color: scheme.foreground,
                                  fontFamily: 'packages/shadcn_ui/GeistMono',
                                )
                            : ShadTheme.of(context)
                                .textTheme
                                .small
                                .copyWith(color: scheme.foreground),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 相对时间：1 天内用「x 分钟/小时前」，更久回退「x 天前」。
  String _fmtRelative(DateTime t, AppLocalizations l10n) {
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inMinutes < 1) return l10n.timeJustNow;
    if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
    return l10n.timeDaysAgo(diff.inDays);
  }
}

/// CPU / 内存占用条：标签 + 动画进度条 + 百分比；>85% 标签旁警告图标。
class _ResourceBar extends StatelessWidget {
  const _ResourceBar({required this.label, required this.percent});

  final String label;
  final double? percent;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final p = percent;
    final shown = p == null ? '—' : '${p.toStringAsFixed(0)}%';
    final color = loadColor(scheme, p);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label,
                    style: theme.textTheme.muted.copyWith(color: scheme.mutedForeground)),
              ),
              if (p != null && p > 85) ...[
                const SizedBox(width: 4),
                Icon(LucideIcons.triangleAlert, size: 13, color: scheme.destructive),
              ],
            ],
          ),
        ),
        Expanded(
          // 轮询更新时进度条平滑过渡，而不是跳变。
          child: p == null
              ? ShadProgress(value: null, color: color)
              : TweenAnimationBuilder<double>(
                  tween: Tween(end: (p / 100).clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => ShadProgress(value: value, color: color),
                ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(shown,
              textAlign: TextAlign.end,
              style:
                  theme.textTheme.small.copyWith(color: scheme.foreground)),
        ),
      ],
    );
  }
}
