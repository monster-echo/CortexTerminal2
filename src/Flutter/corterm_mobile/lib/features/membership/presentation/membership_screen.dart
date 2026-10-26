import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../data/store_purchase_controller.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});
  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  String? _selectedId;
  bool _agreementAccepted = false;

  Future<void> _manage() async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    try {
      final opened = await launchUrl(
        Uri.parse(
          defaultTargetPlatform == TargetPlatform.iOS
              ? 'https://apps.apple.com/account/subscriptions'
              : 'https://play.google.com/store/account/subscriptions',
        ),
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '请打开商店账户中的订阅管理。' : 'Open subscriptions in your store account.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String cn, String en) => zh ? cn : en;
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final store = ref.watch(storePurchaseProvider);
    final controller = ref.read(storePurchaseProvider.notifier);
    final membership = ref.watch(membershipStatusProvider);
    final catalog = ref.watch(membershipPlansProvider);
    final data = membership.asData?.value ?? <String, dynamic>{};
    final isPro = data['tier'] == 'pro' && data['isActive'] != false;
    final lifetime = isPro && data['expiresAtUtc'] == null;
    final expiry = DateTime.tryParse(data['expiresAtUtc'] as String? ?? '');
    String date(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    const order = {'pro_month': 0, 'pro_year': 1, 'pro_lifetime': 2};
    final products = store.products.toList()
      ..sort(
        (a, b) => (order[store.plans[a.id]] ?? 3).compareTo(
          order[store.plans[b.id]] ?? 3,
        ),
      );
    final selected =
        products.where((p) => p.id == _selectedId).firstOrNull ??
        products.where((p) => store.plans[p.id] == 'pro_year').firstOrNull ??
        products.firstOrNull;
    final currentProduct = products
        .where((p) => store.plans[p.id] == data['planCode'])
        .firstOrNull;
    final selectedPlan = selected == null ? null : store.plans[selected.id];
    final subscription =
        selectedPlan == 'pro_month' || selectedPlan == 'pro_year';
    final benefitPlan = catalog.asData?.value
        .where(
          (p) =>
              p['code'] ==
              (isPro ? data['planCode'] : selectedPlan ?? 'pro_year'),
        )
        .firstOrNull;
    final quota = isPro ? data : (benefitPlan ?? <String, dynamic>{});
    final free = catalog.asData?.value
        .where((p) => p['code'] == 'free')
        .firstOrNull;
    final canBuy =
        !isPro &&
        selected != null &&
        !store.loading &&
        !store.busy &&
        !membership.isLoading &&
        !membership.hasError &&
        (!subscription || _agreementAccepted);
    String name(String? plan) => switch (plan) {
      'pro_month' => tr('月度订阅', 'Monthly subscription'),
      'pro_year' => tr('年度订阅', 'Annual subscription'),
      'pro_lifetime' => tr('永久版', 'Lifetime'),
      _ => tr('Pro 会员', 'Pro membership'),
    };
    String period(String? plan) => switch (plan) {
      'pro_month' => tr('每月自动续费', 'Renews monthly'),
      'pro_year' => tr('每年自动续费', 'Renews annually'),
      _ => tr('一次购买，长期使用', 'One-time purchase'),
    };
    Widget panel(List<Widget> children) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    Widget muted(String text) => Text(
      text,
      style: TextStyle(fontSize: 13, height: 1.5, color: c.textSecondary),
    );
    Widget detail(String label, String value, {String? freeValue}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                if (freeValue != null)
                  muted(tr('免费版：$freeValue', 'Free: $freeValue')),
              ],
            ),
          ),
        ],
      ),
    );
    Widget cancelPanel() => panel([
      Text(
        tr('如何取消订阅', 'Canceling your subscription'),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      muted(
        defaultTargetPlatform == TargetPlatform.iOS
            ? tr(
                '在系统设置 → Apple 账户 → 订阅中管理或取消续订。',
                'Manage or cancel renewal in Settings → Apple Account → Subscriptions.',
              )
            : tr(
                '在 Google Play → 付款和订阅 → 订阅中管理或取消续订。',
                'Manage or cancel renewal in Google Play → Payments & subscriptions → Subscriptions.',
              ),
      ),
      const SizedBox(height: 6),
      muted(
        tr(
          '取消续订后，当前已支付周期内的会员权益仍然有效。',
          'After canceling renewal, membership remains available through the paid period.',
        ),
      ),
    ]);
    Widget benefitsPanel() => panel([
      Text(
        tr('会员权益', 'Membership benefits'),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      detail(
        tr('连接电脑', 'Connected computers'),
        '${quota['maxWorkers'] ?? '—'}',
        freeValue: free?['maxWorkers']?.toString(),
      ),
      Divider(height: 1, color: c.divider),
      detail(
        tr('终端回滚额度', 'Terminal scrollback'),
        '${quota['maxScrollbackMegabytes'] ?? '—'} MB',
        freeValue: free == null ? null : '${free['maxScrollbackMegabytes']} MB',
      ),
    ]);

    Future<void> restore() async {
      await controller.restore();
      if (!context.mounted || ref.read(storePurchaseProvider).error != null) {
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
    }

    return AdaptivePageScaffold(
      backgroundColor: c.background,
      appBar: CortermAppBar(
        title: tr('会员', 'Membership'),
        actions: [
          TextButton(
            onPressed: store.busy || !StorePurchaseController.supported
                ? null
                : restore,
            child: Text(
              store.busy
                  ? tr('处理中…', 'Processing…')
                  : tr('恢复购买', 'Restore purchases'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                if (membership.isLoading)
                  const LinearProgressIndicator()
                else if (membership.hasError)
                  panel([
                    muted(
                      tr(
                        '会员信息加载失败，请重试。',
                        'Could not load membership. Please retry.',
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(membershipStatusProvider),
                      child: Text(l10n.retry),
                    ),
                  ])
                else ...[
                  if (isPro) ...[
                    if (expiry != null &&
                        expiry.isAfter(DateTime.now()) &&
                        expiry.difference(DateTime.now()).inDays < 5)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: panel([
                          muted(
                            tr(
                              '会员有效期至 ${date(expiry)}，请在商店查看续订状态。',
                              'Membership is valid until ${date(expiry)}. Check renewal status in your store.',
                            ),
                          ),
                        ]),
                      ),
                    panel([
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 28,
                            color: c.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${l10n.appName} Pro',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lifetime
                                      ? name('pro_lifetime')
                                      : name(data['planCode'] as String?),
                                  style: TextStyle(color: c.accent),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      detail(
                        tr('有效期至', 'Valid until'),
                        lifetime
                            ? tr('永久有效', 'Lifetime')
                            : expiry == null
                            ? '—'
                            : date(expiry),
                      ),
                      if (!lifetime && currentProduct != null)
                        detail(
                          tr('商店当前价格', 'Current store price'),
                          currentProduct.price,
                        ),
                    ]),
                    const SizedBox(height: 20),
                  ] else ...[
                    Text(
                      '${l10n.appName} Pro',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        '连接更多电脑，保留更多终端历史。',
                        'Connect more computers and keep more terminal history.',
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (benefitPlan != null) ...[
                      benefitsPanel(),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      tr('选择套餐', 'Choose a plan'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (store.loading && products.isEmpty) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      muted(tr('正在获取商店价格…', 'Loading store prices…')),
                    ],
                    if (!store.loading && products.isEmpty) ...[
                      const SizedBox(height: 6),
                      panel([
                        Text(
                          tr('暂时无法加载商店套餐', 'Store plans could not be loaded'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        muted(
                          tr(
                            '请确认已登录 App Store 或 Google Play 后重新加载。已购买？可使用右上角“恢复购买”。',
                            'Check that you are signed in to the App Store or Google Play, then reload. Already purchased? Use Restore purchases above.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final code in const [
                          'pro_month',
                          'pro_year',
                          'pro_lifetime',
                        ]) ...[
                          if (code != 'pro_month')
                            Divider(height: 20, color: c.divider),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name(code),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    muted(period(code)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                child: Text(
                                  tr('暂不可用', 'Unavailable'),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: store.busy ? null : controller.load,
                          child: Text(tr('重新加载', 'Reload plans')),
                        ),
                      ]),
                    ],
                    for (final product in products)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Semantics(
                          selected: product.id == selected?.id,
                          button: true,
                          child: Material(
                            color: c.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: store.busy
                                  ? null
                                  : () => setState(() {
                                      _selectedId = product.id;
                                      _agreementAccepted = false;
                                    }),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: product.id == selected?.id
                                        ? c.textPrimary
                                        : c.divider,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      product.id == selected?.id
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: product.id == selected?.id
                                          ? c.textPrimary
                                          : c.textSecondary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name(store.plans[product.id]),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          muted(
                                            period(store.plans[product.id]),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        product.price,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (subscription) ...[
                      const SizedBox(height: 6),
                      muted(
                        tr(
                          '确认购买后由商店账户扣款。订阅将自动续费，续费价格与周期以商店确认页为准。',
                          'Payment is charged to your store account after confirmation. Subscriptions renew automatically; review the price and billing period in the store.',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _agreementAccepted,
                        onChanged: store.busy
                            ? null
                            : (value) => setState(
                                () => _agreementAccepted = value ?? false,
                              ),
                        title: muted(
                          tr(
                            '我已了解自动续费及下方取消订阅说明',
                            'I understand automatic renewal and the cancellation instructions below',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (selected != null)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.emphasis,
                          foregroundColor: c.onEmphasis,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: canBuy
                            ? () => controller.buy(selected)
                            : null,
                        child: Text(
                          store.busy
                              ? tr('正在处理…', 'Processing…')
                              : '${tr('购买', 'Buy')} · ${selected.price}',
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (subscription)
                      cancelPanel()
                    else if (selectedPlan == 'pro_lifetime')
                      muted(
                        tr(
                          '永久版为一次性购买，不会自动续费。最终价格以商店确认页为准。',
                          'Lifetime is a one-time purchase with no automatic renewal. Confirm the final price in the store.',
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                  if (isPro) ...[benefitsPanel(), const SizedBox(height: 16)],
                  if (isPro && !lifetime) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.emphasis,
                        foregroundColor: c.onEmphasis,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed:
                          store.busy || !StorePurchaseController.supported
                          ? null
                          : _manage,
                      child: Text(tr('管理订阅', 'Manage subscription')),
                    ),
                    const SizedBox(height: 16),
                    cancelPanel(),
                  ],
                ],
                if (catalog.hasError) ...[
                  const SizedBox(height: 16),
                  muted(tr('权益信息暂不可用。', 'Benefit details are unavailable.')),
                  TextButton(
                    onPressed: () => ref.invalidate(membershipPlansProvider),
                    child: Text(l10n.retry),
                  ),
                ],
                if (store.error != null && store.errorPhase != 'catalog') ...[
                  const SizedBox(height: 16),
                  Text(
                    tr(
                      '暂时未能完成操作。已付款的订单可重试验证或恢复购买。',
                      'The operation could not be completed. For paid orders, retry verification or restore purchases.',
                    ),
                    style: TextStyle(color: c.danger, height: 1.5),
                  ),
                  TextButton(
                    onPressed: store.busy
                        ? null
                        : () async {
                            await controller.load();
                            if (mounted) await controller.retryVerification();
                          },
                    child: Text(l10n.retry),
                  ),
                ],
                if (!StorePurchaseController.supported)
                  muted(
                    tr(
                      '此平台不支持应用内购买。',
                      'In-app purchases are unavailable on this platform.',
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.push('/settings/redeem'),
                  child: Text(tr('兑换会员码', 'Redeem a code')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
