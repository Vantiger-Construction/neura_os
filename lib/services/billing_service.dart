import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class BillingService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  /// All successfully verified purchases for the current session.
  final ValueNotifier<List<PurchaseDetails>> purchases =
      ValueNotifier<List<PurchaseDetails>>([]);

  /// Whether a premium entitlement is currently active.
  bool get isPremium => purchases.value.any(
        (p) => p.status == PurchaseStatus.purchased ||
            p.status == PurchaseStatus.restored,
      );

  /// Initializes the billing connection, subscribes to the purchase stream,
  /// and restores any past purchases.
  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) return;

    unawaited(_purchaseSub?.cancel());
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) => debugPrint('BillingService: stream error $e'),
    );

    // Restore previously-completed purchases (e.g. after reinstall).
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> updates) {
    final current = List<PurchaseDetails>.from(purchases.value);
    for (final purchase in updates) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        debugPrint('BillingService: purchase error for ${purchase.productID}');
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final existing = current.indexWhere((p) => p.productID == purchase.productID);
        if (existing >= 0) {
          current[existing] = purchase;
        } else {
          current.add(purchase);
        }
      }

      // Acknowledge the purchase to avoid being refunded.
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
    purchases.value = current;
  }

  /// Fetches product details for the given product [ids].
  Future<List<ProductDetails>> fetchProducts(List<String> ids) async {
    final response = await _iap.queryProductDetails(ids.toSet());
    if (response.error != null) {
      debugPrint('BillingService: query error ${response.error}');
    }
    return response.productDetails;
  }

  /// Starts the purchase flow for [product].
  Future<void> purchase(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Restores previous purchases.
  Future<void> restorePurchases() async => _iap.restorePurchases();

  /// Disposes the purchase stream subscription.
  void dispose() {
    _purchaseSub?.cancel();
    _purchaseSub = null;
  }
}
