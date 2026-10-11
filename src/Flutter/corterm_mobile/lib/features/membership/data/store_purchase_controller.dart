import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_controller.dart';

final membershipStatusProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(apiClientProvider).getMap('/api/billing/subscription'),
);

final membershipPlansProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final plans = await ref
      .watch(apiClientProvider)
      .getList('/api/billing/plans');
  return plans.cast<Map<String, dynamic>>();
});

class StoreState {
  const StoreState({
    this.loading = true,
    this.busy = false,
    this.error,
    this.products = const [],
    this.plans = const {},
  });
  final bool loading;
  final bool busy;
  final String? error;
  final List<ProductDetails> products;
  final Map<String, String> plans;
}

final storePurchaseProvider =
    StateNotifierProvider<StorePurchaseController, StoreState>((ref) {
      final auth = ref.watch(authProvider);
      return StorePurchaseController(
        ref,
        auth.status == AuthStatus.authenticated,
      );
    });

/// Listen for unfinished transactions for the lifetime of the authenticated app.
/// Complete/acknowledge a paid purchase only after the Gateway grants entitlement.
class StorePurchaseController extends StateNotifier<StoreState> {
  StorePurchaseController(this.ref, bool authenticated)
    : super(const StoreState()) {
    if (!supported || !authenticated) {
      state = const StoreState(loading: false);
      return;
    }
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      (items) {
        _queue = _queue
            .then((_) async {
              for (final item in items) {
                await _handle(item);
              }
            })
            .catchError((Object error) {
              if (mounted) _set(busy: false, error: '$error');
            });
      },
      onError: (Object error) {
        if (mounted) _set(busy: false, error: '$error');
      },
    );
    unawaited(_initialize());
  }
  Future<void> _initialize() async {
    await load();
    if (mounted && platform == 'google') await restore(clearError: false);
  }

  final Ref ref;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future.value();
  final Map<String, PurchaseDetails> _retry = {};
  final Set<String> _delivered = {};
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'apple' : 'google';
  void _set({
    bool? loading,
    bool? busy,
    String? error,
    bool clearError = false,
    List<ProductDetails>? products,
    Map<String, String>? plans,
  }) {
    if (!mounted) return;
    state = StoreState(
      loading: loading ?? state.loading,
      busy: busy ?? state.busy,
      error: clearError ? error : error ?? state.error,
      products: products ?? state.products,
      plans: plans ?? state.plans,
    );
  }

  Future<void> load() async {
    if (!supported || !mounted) return;
    _set(loading: true, products: const [], clearError: true);
    try {
      final catalog = await ref
          .read(apiClientProvider)
          .getMap('/api/iap/catalog', query: {'platform': platform});
      if (catalog['available'] != true) {
        throw StateError(
          'Purchases are temporarily unavailable. Please try again later.',
        );
      }
      final plans = <String, String>{
        for (final p in catalog['products'] as List<dynamic>)
          p['productId'] as String: p['planCode'] as String,
      };
      if (!await InAppPurchase.instance.isAvailable()) {
        throw StateError('The app store is unavailable.');
      }
      final response = await InAppPurchase.instance.queryProductDetails(
        plans.keys.toSet(),
      );
      if (response.error != null) throw StateError(response.error!.message);
      _set(
        loading: false,
        products: response.productDetails,
        plans: plans,
        error: response.notFoundIDs.isEmpty
            ? null
            : 'Some products are unavailable: ${response.notFoundIDs.join(', ')}',
      );
    } catch (e) {
      _set(loading: false, busy: false, error: '$e');
    }
  }

  Future<void> buy(ProductDetails product) async {
    if (state.busy || !supported) return;
    _set(busy: true, clearError: true);
    try {
      String? account;
      if (platform == 'google') {
        final token = ref.read(apiClientProvider).tokenStore.token;
        if (token == null) throw StateError('Please sign in again.');
        final payload = jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(token.split('.')[1])),
          ),
        ) as Map<String, dynamic>;
        account = sha256
            .convert(utf8.encode(payload['sub'] as String))
            .toString();
      }
      final accepted = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: account,
        ),
      );
      if (!accepted) {
        _set(busy: false, error: 'The store did not start the purchase.');
      }
    } catch (e) {
      _set(loading: false, busy: false, error: '$e');
    }
  }

  Future<void> restore({bool clearError = true}) async {
    if (state.busy || !supported) return;
    _set(busy: true, clearError: clearError);
    try {
      await InAppPurchase.instance.restorePurchases();
      await _queue;
      if (!mounted) return;
      ref.invalidate(membershipStatusProvider);
      _set(busy: false, error: state.error);
    } catch (e) {
      _set(loading: false, busy: false, error: '$e');
    }
  }

  Future<void> retryVerification() async {
    if (state.busy) return;
    _queue = _queue.then((_) async {
      for (final purchase in _retry.values.toList()) {
        await _handle(purchase);
      }
    });
    await _queue;
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    if (!mounted) return;
    if (purchase.status == PurchaseStatus.pending) {
      _set(busy: true, clearError: true);
      return;
    }
    if (purchase.status == PurchaseStatus.error ||
        purchase.status == PurchaseStatus.canceled) {
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
      _set(busy: false, error: purchase.error?.message);
      return;
    }
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return;
    }
    final key =
        '${purchase.productID}:${purchase.purchaseID ?? purchase.verificationData.serverVerificationData}';
    _retry[key] = purchase;
    _set(busy: true, clearError: true);
    try {
      if (!_delivered.contains(key)) {
        final data = purchase.verificationData.serverVerificationData;
        if (data.isEmpty) {
          throw StateError('The store returned an empty purchase receipt.');
        }
        await ref.read(apiClientProvider).postMap('/api/iap/purchase/verify', {
          'platform': platform,
          'productId': purchase.productID,
          if (platform == 'google') 'purchaseToken': data,
          if (platform == 'apple') ...{
            'signedTransaction': data,
            'receiptFormat': data.split('.').length == 3 ? 'jws' : 'legacy',
          },
        });
        if (!mounted) return;
        _delivered.add(key);
        ref.invalidate(membershipStatusProvider);
      }
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
      _retry.remove(key);
      _set(busy: false, clearError: true);
    } catch (e) {
      _set(loading: false, busy: false, error: '$e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
