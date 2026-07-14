import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/supabase/supabase_service.dart';

/// Foundation service for Google Play Billing / Apple StoreKit coin purchases.
///
/// Security contract:
///   * This service NEVER credits coins. On a completed store purchase it only
///     forwards the purchase token to the server via the `record_iap_purchase`
///     RPC, which records a PENDING receipt. Coins are granted later, only by
///     the server after it verifies the receipt with Google/Apple.
///   * The coin amount per product is decided server-side (iap_products); the
///     client only knows product IDs.
///
/// This is the foundation layer: it is not yet wired into the coin-purchase UI
/// (manual recharge stays as-is), and no live crediting happens until the
/// verification Edge Function is implemented.
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  /// Store SKUs for coin packs. These must match both the store consoles and
  /// the `iap_products` catalog rows.
  static const String coins100k = 'coins_100k';
  static const String coins500k = 'coins_500k';
  static const String coins1m = 'coins_1m';
  static const String coins5m = 'coins_5m';

  static const Set<String> coinProductIds = {
    coins100k,
    coins500k,
    coins1m,
    coins5m,
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _initialized = false;

  /// Whether the underlying store billing is available on this device.
  Future<bool> isAvailable() => _iap.isAvailable();

  /// Starts listening to the purchase stream. Safe to call once at startup.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('[IAP] purchaseStream error: $e'),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }

  /// Loads store product details for the coin SKUs.
  Future<List<ProductDetails>> loadProducts() async {
    if (!await _iap.isAvailable()) return const [];
    final response = await _iap.queryProductDetails(coinProductIds);
    return response.productDetails;
  }

  /// Launches the store purchase flow for a coin product. The result arrives
  /// asynchronously on the purchase stream (handled by [_onPurchases]).
  Future<void> buyCoins(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    // Coins are consumable — buyConsumable lets the user repurchase.
    await _iap.buyConsumable(purchaseParam: param);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await _recordReceipt(p);
      }
      // The purchase must always be completed to remove it from the queue,
      // regardless of our server-side verification outcome.
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  /// Forwards the purchase token to the server as a PENDING receipt. Does NOT
  /// grant coins — the server verifies and credits separately.
  Future<void> _recordReceipt(PurchaseDetails p) async {
    try {
      final client = SupabaseService.client;
      if (client == null || client.auth.currentUser == null) return;
      final token = p.verificationData.serverVerificationData;
      if (token.isEmpty) return;
      await client.rpc('record_iap_purchase', params: {
        'p_product_id': p.productID,
        'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'p_purchase_token': token,
      });
    } catch (e) {
      // Never surface store internals to the user here; the receipt can be
      // reconciled server-side from the store's own record if this fails.
      debugPrint('[IAP] record receipt failed: $e');
    }
  }
}
