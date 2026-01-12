import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';

class BillingService {
  final InAppPurchase _iap = InAppPurchase.instance;

  /// Initializes connection to the billing service.
  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) {
      // Handle unavailability
    }
    // TODO: load past purchases, listen to purchase updates
  }

  /// Fetches product details for subscription tiers.
  Future<List<ProductDetails>> fetchProducts(List<String> ids) async {
    final response = await _iap.queryProductDetails(ids.toSet());
    return response.productDetails;
  }

  /// Starts purchase process for a product.
  Future<void> purchase(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Restores previous purchases.
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }
}
