import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../data/store_purchase_controller.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});
  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  String? _selectedId;
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String cn, String en) => zh ? cn : en;
    final c = colorsOf(context);
    final store = ref.watch(storePurchaseProvider);
    final controller = ref.read(storePurchaseProvider.notifier);
    final membership = ref.watch(membershipStatusProvider);
    final plans = ref.watch(membershipPlansProvider);
    final isPro = membership.value?['tier'] == 'pro';
    final lifetime = isPro && membership.value?['expiresAtUtc'] == null;
    final expiry = DateTime.tryParse(
      membership.value?['expiresAtUtc'] as String? ?? '',
    );
    final products = store.products.toList()
      ..sort(
        (a, b) =>
            (const {
                      'pro_month': 0,
                      'pro_year': 1,
                      'pro_lifetime': 2,
                    }[store.plans[a.id]] ??
                    3)
                .compareTo(
                  const {
                        'pro_month': 0,
                        'pro_year': 1,
                        'pro_lifetime': 2,
                      }[store.plans[b.id]] ??
                      3,
                ),
      );
    final selected =
        products.where((p) => p.id == _selectedId).firstOrNull ??
        products.where((p) => store.plans[p.id] == 'pro_year').firstOrNull ??
        products.firstOrNull;
    final selectedPlan = selected == null ? null : store.plans[selected.id];
    final benefits = plans.value
        ?.where((p) => p['code'] == (selectedPlan ?? 'pro_year'))
        .firstOrNull;
    // Keep an existing subscription in store management, avoiding simultaneous
    // monthly/yearly subscriptions. A lifetime upgrade remains available.
    final canBuy =
        selected != null &&
        !store.busy &&
        !membership.isLoading &&
        !membership.hasError &&
        !lifetime &&
        (!isPro || selectedPlan == 'pro_lifetime');
    String name(String? plan) => switch (plan) {
      'pro_month' => tr('月度订阅', 'Monthly subscription'),
      'pro_year' => tr('年度订阅', 'Annual subscription'),
      'pro_lifetime' => tr('永久版', 'Lifetime'),
      _ => 'Pro',
    };
    return Scaffold(
      appBar: AppBar(title: Text(tr('会员', 'Membership'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Corterm Pro',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.meBenefitsHint,
              style: TextStyle(color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: membership.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => TextButton(
                  onPressed: () => ref.invalidate(membershipStatusProvider),
                  child: Text(
                    tr(
                      '会员信息加载失败，点击重试',
                      'Membership unavailable. Tap to retry.',
                    ),
                  ),
                ),
                data: (_) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPro
                          ? (lifetime
                                ? tr('Pro 永久会员', 'Pro lifetime member')
                                : tr('Pro 会员', 'Pro member'))
                          : tr('当前为免费账户', 'Current plan: Free'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (expiry != null)
                      Text(
                        '${tr('有效期至', 'Valid until')} ${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}',
                        style: TextStyle(color: c.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
            if (benefits != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        '最多连接 ${benefits['maxWorkers']} 台电脑',
                        'Connect up to ${benefits['maxWorkers']} computers',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        '终端回滚额度 ${benefits['maxScrollbackMegabytes']} MB',
                        'Terminal scrollback quota: ${benefits['maxScrollbackMegabytes']} MB',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (!StorePurchaseController.supported)
              Text(
                tr(
                  '此平台不支持应用内购买。',
                  'In-app purchases are unavailable on this platform.',
                ),
              ),
            if (store.loading) const LinearProgressIndicator(),
            if (store.error != null) ...[
              Text(
                tr(
                  '暂时未能完成操作。请检查网络后重试；已付款的订单可以重试验证或恢复购买。',
                  'The operation could not be completed. Check your connection and retry. For paid orders, retry verification or restore purchases.',
                ),
                style: TextStyle(color: c.danger),
              ),
              TextButton(
                onPressed: store.busy
                    ? null
                    : () async {
                        await controller.load();
                        if (mounted) await controller.retryVerification();
                      },
                child: Text(tr('重试', 'Retry')),
              ),
            ],
            for (final product in products)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  selected: product.id == selected?.id,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: store.busy
                        ? null
                        : () => setState(() => _selectedId = product.id),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: product.id == selected?.id
                              ? c.accent
                              : c.divider,
                          width: product.id == selected?.id ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            product.id == selected?.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: product.id == selected?.id
                                ? c.accent
                                : c.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name(store.plans[product.id]),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  store.plans[product.id] == 'pro_lifetime'
                                      ? tr('一次购买，长期使用', 'One-time purchase')
                                      : tr(
                                          '自动续费，可随时取消续订',
                                          'Auto-renews. Cancel renewal anytime.',
                                        ),
                                  style: TextStyle(color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              product.price,
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (products.isNotEmpty)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onEmphasis,
                ),
                onPressed: canBuy ? () => controller.buy(selected) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    store.busy
                        ? tr('正在处理…', 'Processing…')
                        : lifetime
                        ? tr('已拥有永久会员', 'Lifetime membership active')
                        : '${tr('购买', 'Buy')} ${selected?.price ?? ''}',
                  ),
                ),
              ),
            if (isPro && !lifetime)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  tr(
                    '你已有 Pro 权益。订阅请在商店中管理，购买永久版后请取消原订阅，避免继续扣款。',
                    'You already have Pro. Manage your subscription in the store. After purchasing lifetime access, cancel your existing subscription to stop future charges.',
                  ),
                  style: TextStyle(color: c.textSecondary),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              tr(
                '订阅会自动续费，可在商店账户中管理或取消。永久版为一次性购买。最终价格以商店确认页为准。',
                'Subscriptions renew automatically and can be managed or canceled in your store account. Lifetime is a one-time purchase. Confirm the final price in the store.',
              ),
              style: TextStyle(color: c.textSecondary),
            ),
            TextButton(
              onPressed: store.busy || !StorePurchaseController.supported
                  ? null
                  : () async {
                      await controller.restore();
                      if (!context.mounted ||
                          ref.read(storePurchaseProvider).error != null) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              '已请求恢复购买，权益会在验证后更新。',
                              'Restore requested. Membership updates after verification.',
                            ),
                          ),
                        ),
                      );
                    },
              child: Text(tr('恢复购买', 'Restore purchases')),
            ),
            if (StorePurchaseController.supported)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    defaultTargetPlatform == TargetPlatform.iOS
                        ? 'https://apps.apple.com/account/subscriptions'
                        : 'https://play.google.com/store/account/subscriptions',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(tr('管理订阅', 'Manage subscription')),
              ),
            TextButton(
              onPressed: () => context.push('/settings/redeem'),
              child: Text(tr('兑换会员码', 'Redeem a code')),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => context.push('/legal/terms'),
                  child: Text(tr('服务条款', 'Terms of service')),
                ),
                TextButton(
                  onPressed: () => context.push('/legal/privacy'),
                  child: Text(tr('隐私政策', 'Privacy policy')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
