import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../app/theme/corterm_theme.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/list_group.dart';
import '../../profile/presentation/profile_screen.dart';
import '../data/store_purchase_controller.dart';

/// Account, membership and help. Personalization lives in Settings.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final c = colorsOf(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String cn, String en) => zh ? cn : en;
    final auth = ref.watch(authProvider);
    final profile = ref.watch(profileProvider).value;
    final displayName = profile?.displayName?.trim();
    final membership = ref.watch(membershipStatusProvider);
    final isPro = membership.value?['tier'] == 'pro';
    final expiry = DateTime.tryParse(
      membership.value?['expiresAtUtc'] as String? ?? '',
    );
    return AppShellScaffold(
      tab: ShellTab.me,
      title: l10n.meTitle,
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.settings),
          tooltip: l10n.settings,
          onPressed: () => context.push('/settings'),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider);
          ref.invalidate(membershipStatusProvider);
          await ref.read(membershipStatusProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            AppGroupCard(
              children: [
                AppRow(
                  icon: LucideIcons.user,
                  label: (displayName != null && displayName.isNotEmpty)
                      ? displayName
                      : auth.username ?? l10n.meTitle,
                  value: l10n.profileTitle,
                  chevron: true,
                  onTap: () => context.push('/settings/profile'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppGroupCard(
              children: [
                AppRow(
                  icon: LucideIcons.circleCheck,
                  label: membership.isLoading
                      ? tr('正在加载会员…', 'Loading membership…')
                      : membership.hasError
                      ? tr('会员信息暂不可用', 'Membership unavailable')
                      : isPro
                      ? 'Corterm Pro'
                      : tr('免费账户', 'Free account'),
                  value: isPro
                      ? (expiry == null
                            ? tr('永久版', 'Lifetime')
                            : '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}')
                      : tr('查看 Pro 权益', 'Explore Pro'),
                  chevron: true,
                  onTap: () => context.push('/settings/membership'),
                ),
              ],
            ),
            if (membership.hasError)
              TextButton(
                onPressed: () => ref.invalidate(membershipStatusProvider),
                child: Text(
                  tr('会员信息加载失败，点击重试', 'Membership unavailable. Tap to retry.'),
                  style: TextStyle(color: c.danger),
                ),
              ),
            const SizedBox(height: 16),
            AppGroupCard(
              children: [
                AppRow(
                  icon: LucideIcons.shieldCheck,
                  label: tr('账户与安全', 'Account and security'),
                  chevron: true,
                  onTap: () => context.push('/settings/security'),
                ),
                AppRow(
                  icon: LucideIcons.headphones,
                  label: l10n.supportTitle,
                  chevron: true,
                  onTap: () => context.push('/settings/support'),
                ),
                AppRow(
                  icon: LucideIcons.messageSquare,
                  label: l10n.feedbackTitle,
                  chevron: true,
                  onTap: () => context.push('/settings/feedback'),
                ),
                AppRow(
                  icon: LucideIcons.info,
                  label: l10n.about,
                  chevron: true,
                  onTap: () => context.push('/settings/about'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
