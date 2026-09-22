import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../data/membership_repository.dart';

/// 商店详情页（评分、分享共用），与 docs/producthunt-launch.md 公布的一致：
/// - iOS:    https://apps.apple.com/us/app/corterm/id6767838640
/// - Android: https://play.google.com/store/apps/details?id=top.rwecho.cortexterminal
const kAppleAppStoreUrl = 'https://apps.apple.com/us/app/corterm/id6767838640';
const kGooglePlayUrl =
    'https://play.google.com/store/apps/details?id=top.rwecho.cortexterminal';

/// 按当前平台返回对应商店页；web/未知平台给 Play 链接（分享文案里最通用）。
final storeUrlProvider = Provider<String>((ref) {
  if (kIsWeb) return kGooglePlayUrl;
  if (defaultTargetPlatform == TargetPlatform.iOS) return kAppleAppStoreUrl;
  return kGooglePlayUrl;
});

/// 「评分」直达链接：iOS 用 write-review 深链，点开直接弹 App Store 的
/// 评分页（不用再找评分按钮）；Android 的 Play 商店没有等价深链，
/// 只能到详情页（详情页里有「 write review 」入口）。
final reviewUrlProvider = Provider<String>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return 'itms-apps://itunes.apple.com/app/id6767838640?action=write-review';
  }
  return ref.read(storeUrlProvider);
});

/// 我的（§50 对齐 ArkTS SettingsPage 用户区）：用户头 → 会员权益（订阅 + 兑换）
/// → 评分 / 分享 → 设置入口。侧边栏底部用户行直达此页。
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final subscription = ref.watch(subscriptionProvider);

    return AppShellScaffold(
      tab: ShellTab.me,
      title: l10n.meTitle,
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

          // ---- 会员权益 ----
          AppGroupHeader(l10n.benefitsTitle),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.crown,
              label: l10n.benefitsTitle,
              value: subscription.valueOrNull?._tierLabel(l10n) ?? '…',
              chevron: true,
              onTap: () => _showBenefits(context, ref),
            ),
            AppRow(
              icon: LucideIcons.ticket,
              label: l10n.redeemCodeLabel,
              chevron: true,
              onTap: () => _redeem(context, ref),
            ),
          ]),

          // ---- 评分 / 分享 ----
          AppGroupHeader(l10n.shareApp),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.star,
              label: l10n.rateUs,
              chevron: true,
              onTap: () => _rate(context, ref),
            ),
            AppRow(
              icon: LucideIcons.share2,
              label: l10n.shareApp,
              chevron: true,
              onTap: () => _share(context, ref),
            ),
          ]),

          // ---- 设置 ----
          AppGroupHeader(l10n.settings),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.settings,
              label: l10n.settings,
              chevron: true,
              onTap: () => context.push('/settings'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _showBenefits(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final subscription = await ref.read(subscriptionProvider.future);
    if (!context.mounted) return;
    await showCortermSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.benefitsTitle,
                    style: ShadTheme.of(sheetContext).textTheme.large),
                const SizedBox(height: 16),
                _BenefitRow(
                    label: l10n.benefitsTitle,
                    value: subscription._tierLabel(l10n)),
                _BenefitRow(
                  label: l10n.membershipExpires,
                  value: subscription.expiresAtUtc == null
                      ? l10n.membershipNoExpiry
                      : _fmt(subscription.expiresAtUtc!),
                ),
                if (subscription.maxWorkers != null)
                  _BenefitRow(
                      label: l10n.quotaWorkers,
                      value: '${subscription.maxWorkers}'),
                if (subscription.maxScrollbackMegabytes != null)
                  _BenefitRow(
                      label: l10n.quotaScrollback,
                      value: '${subscription.maxScrollbackMegabytes} MB'),
                const SizedBox(height: 8),
                ShadButton.outline(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(AppLocalizations.of(sheetContext)!.cancel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmt(DateTime utc) {
    final local = utc.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _redeem(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final code = await showCortermSheetDialog<String>(
      context: context,
      title: l10n.redeemCodeLabel,
      child: ShadInputFormField(
        controller: controller,
        placeholder: Text(l10n.redeemCodeLabel),
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ShadButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(l10n.redeemAction),
        ),
      ],
    );
    if (code == null || code.isEmpty) return;
    try {
      await ref.read(membershipRepositoryProvider).redeem(code);
      ref.invalidate(subscriptionProvider);
      if (context.mounted) showAppToast(context, l10n.redeemSuccess);
    } on ApiException catch (e) {
      if (context.mounted) {
        showAppToast(context, e.serverMessage ?? '$e', destructive: true);
      }
    }
  }

  /// iOS 直达写评论（write-review 深链）；深链打不开时退回商店详情页。
  /// 对齐 ArkTS 的失败 toast（rate_failed）。
  Future<void> _rate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    Future<bool> open(String url) => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
    try {
      if (await open(ref.read(reviewUrlProvider))) return;
      if (await open(ref.read(storeUrlProvider))) return;
      throw StateError('launchUrl returned false');
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, l10n.rateFailed('$e'), destructive: true);
      }
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    await SharePlus.instance.share(
      ShareParams(text: l10n.shareAppText(ref.read(storeUrlProvider))),
    );
  }
}

extension _SubscriptionLabel on BillingSubscription {
  String _tierLabel(AppLocalizations l10n) {
    if (tier.toLowerCase() == 'free' || !isActive) return l10n.membershipFree;
    return planCode?.isNotEmpty ?? false ? planCode! : tier;
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.small)),
          Text(value,
              style: theme.textTheme.small
                  .copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
