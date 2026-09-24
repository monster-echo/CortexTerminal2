import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/states.dart';
import '../data/membership_repository.dart';

/// 分享赚收益（对齐 HarmonyOS ReferralPage / Gateway referral 端点）：
/// 邀请码展示 + 复制 + 系统分享，收益记录，绑定好友邀请码。
class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _applyController = TextEditingController();
  bool _applying = false;

  @override
  void dispose() {
    _applyController.dispose();
    super.dispose();
  }

  Future<void> _share(String code) async {
    final l10n = AppLocalizations.of(context)!;
    await SharePlus.instance.share(
      ShareParams(text: '${l10n.referralShareText}\n\n$code'),
    );
  }

  Future<void> _apply() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _applyController.text.trim();
    if (code.isEmpty || _applying) return;
    setState(() => _applying = true);
    try {
      await ref.read(membershipRepositoryProvider).applyReferralCode(code);
      if (mounted) {
        showAppToast(context, l10n.applyInviteSuccess);
        _applyController.clear();
        ref.invalidate(referralSummaryProvider);
      }
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.serverMessage ?? '${e.statusCode}');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = colorsOf(context);
    final summary = ref.watch(referralSummaryProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: CortermAppBar(
        title: l10n.referral,
        leading: ShadIconButton.ghost(
          foregroundColor: c.textPrimary,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: summary.when(
        loading: () => const Center(child: ShadProgress(value: null)),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(referralSummaryProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            Text(l10n.referralSubtitle,
                style: _mutedTextStyle(context)),
            const SizedBox(height: 16),
            // 邀请码卡片
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text(l10n.myInviteCode,
                    style: _mutedTextStyle(context)?.copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                Text(
                  data.code,
                  style: _mutedTextStyle(context)?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ShadButton.outline(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: data.code));
                      showAppToast(context, l10n.copied);
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.copy, size: 14),
                      const SizedBox(width: 6),
                      Text(l10n.copy),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  ShadButton(
                    onPressed: () => _share(data.code),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.share2, size: 14),
                      const SizedBox(width: 6),
                      Text(l10n.share),
                    ]),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            // 统计
            AppGroupCard(children: [
              AppRow(
                icon: LucideIcons.users,
                label: l10n.friendsInvited,
                value: '${data.invitedCount}',
              ),
              AppRow(
                icon: LucideIcons.calendarDays,
                label: l10n.daysEarned,
                value: '+${data.totalRewardDays}',
              ),
              AppRow(
                icon: LucideIcons.gift,
                label: l10n.rewardPerInvite,
                value: '+${data.rewardDaysPerInvite}',
              ),
            ]),
            const SizedBox(height: 8),
            // 收益记录
            AppGroupHeader(l10n.rewardHistory),
            if (data.rewards.isEmpty)
              AppGroupCard(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(l10n.rewardsEmpty,
                      style: _mutedTextStyle(context)?.copyWith(fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              ])
            else
              AppGroupCard(
                children: data.rewards
                    .map((r) => AppRow(
                          icon: LucideIcons.badgeCheck,
                          label: 'r.invitedUsername',
                          value: '+${r.rewardDays}',
                        ))
                    .toList(),
              ),
            const SizedBox(height: 8),
            // 绑定好友邀请码
            AppGroupHeader(l10n.haveFriendsCode),
            AppGroupCard(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: ShadInput(
                      controller: _applyController,
                      placeholder: Text(l10n.redeemPlaceholder),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton(
                    onPressed: _applying ? null : _apply,
                    child: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l10n.applyInvite),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  TextStyle? _mutedTextStyle(BuildContext context) => ShadTheme.of(context)
      .textTheme
      .muted
      .copyWith(color: colorsOf(context).textPrimary);
}
