import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../app/theme/corterm_theme.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/connection_status_dot.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../session/widgets/session_status.dart';

/// 我的：上面强调会员权益（hero 卡：权益说明 + 兑换 / 邀请返利入口），
/// 下面是 Worker 概况与统计（压栈进入，可返回）；右上角齿轮进设置。
/// 侧边栏底部用户行直达此页。
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);

    return AppShellScaffold(
      tab: ShellTab.me,
      title: l10n.meTitle,
      actions: [
        // 右上角设置入口：压栈进入，设置页带返回键。
        Builder(
          builder: (innerContext) => ShadIconButton.ghost(
            foregroundColor: colorsOf(innerContext).textPrimary,
            icon: const Icon(LucideIcons.settings, size: 20),
            onPressed: () => context.push('/settings'),
          ),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ---- 用户头：点头像/姓名进资料页 ----
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.user,
              label: auth.username ?? l10n.meTitle,
              value: l10n.profileTitle,
              chevron: true,
              onTap: () => context.push('/settings/profile'),
            ),
          ]),

          // ---- 会员权益 hero 卡：整块强调 ----
          const _BenefitsHero(),

          // ---- Worker 概况与统计（?from=me：Workers 页显示返回键）----
          AppGroupHeader(l10n.meStatsTitle),
          const _WorkerStatsCard(),
        ],
      ),
    );
  }
}

/// 会员权益 hero 卡：品牌色强调底 + 权益提示 + 兑换码 / 邀请返利两个入口。
class _BenefitsHero extends ConsumerWidget {
  const _BenefitsHero();

  /// 打开网关 web 控制台定价页（购买在 web 完成，对齐 Harmony MembershipPage）。
  Future<void> _openPricing(BuildContext context, WidgetRef ref) async {
    final base = ref.read(appConfigProvider).replaceAll(RegExp(r'/+$'), '');
    final url = '$base/pricing';
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) throw StateError('launchUrl returned false for $url');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.crown,
                  size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.benefitsTitle,
                    style: theme.textTheme.large.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.meBenefitsHint,
            style: theme.textTheme.muted.copyWith(
                color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 16),
          // Wrap 而非 Row+Expanded：按钮保持自然宽度并换行，
          // 长文案（如 Manage membership）不会被压缩到内部 Row 溢出。
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ShadButton(
                backgroundColor: Colors.white,
                foregroundColor: c.accent,
                // IAP / 会员购买：购买在 web 控制台完成，打开网关定价页。
                onPressed: () => _openPricing(context, ref),
                child: Text(l10n.meOpenMembership),
              ),
              ShadButton.outline(
                foregroundColor: Colors.white,
                decoration: ShadDecoration(
                  border: ShadBorder.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    radius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => context.push('/settings/redeem'),
                child: Text(l10n.redeemCode),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Worker 概况卡：在线数 / 会话总数 / 平均 CPU / 平均内存 2×2 统计格
/// + Worker 状态行 + 查看全部（全部压栈进入，可返回）。
class _WorkerStatsCard extends ConsumerWidget {
  const _WorkerStatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final workers = ref.watch(workersProvider);

    return workers.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: SmallSpinner()),
      ),
      error: (e, _) => ErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(workersProvider),
      ),
      data: (list) {
        final online = list.where((w) => w.isOnline).length;
        final sessions = list.fold<int>(0, (sum, w) => sum + w.sessionCount);
        final cpuList = list.where((w) => w.cpuUsagePercent != null).toList();
        final avgCpu = cpuList.isEmpty
            ? null
            : cpuList.map((w) => w.cpuUsagePercent!).reduce((a, b) => a + b) /
                cpuList.length;
        final memList =
            list.where((w) => w.memoryUsagePercent != null).toList();
        final avgMem = memList.isEmpty
            ? null
            : memList.map((w) => w.memoryUsagePercent!).reduce((a, b) => a + b) /
                memList.length;

        return AppGroupCard(children: [
          if (list.isEmpty)
            AppRow(
              icon: LucideIcons.server,
              label: l10n.meNoWorkers,
              value: l10n.workersTitle,
              chevron: true,
              onTap: () => context.push('/workers?from=me'),
            )
          else ...[
            // 2×2 统计格：宽间距 + 上下分割，避免四格挤在一行。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _Stat(
                              label: '$online/${list.length}',
                              caption: l10n.workersTitle)),
                      Expanded(
                          child: _Stat(
                              label: '$sessions', caption: l10n.meStatSessions)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _Stat(
                              label: avgCpu == null ? '—' : '${avgCpu.toStringAsFixed(0)}%',
                              caption: l10n.meStatCpu)),
                      Expanded(
                          child: _Stat(
                              label: avgMem == null ? '—' : '${avgMem.toStringAsFixed(0)}%',
                              caption: l10n.meStatMemory)),
                    ],
                  ),
                ],
              ),
            ),
            for (final w in list.take(3))
              AppRow(
                leadingWidget: ConnectionStatusDot(
                  color: workerDotColor(colorsOf(context), w),
                ),
                label: w.displayName,
                value: w.isOnline ? l10n.workerOnline : l10n.workerOffline,
                onTap: () => context.push('/workers?from=me'),
              ),
            AppRow(
              label: l10n.meViewAllWorkers,
              value: l10n.workersTitle,
              chevron: true,
              onTap: () => context.push('/workers?from=me'),
            ),
          ],
        ]);
      },
    );
  }
}

/// 单个统计块：大数字在上 + 小标签在下，居中，留足呼吸感。
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.caption});

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              theme.textTheme.muted.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}
