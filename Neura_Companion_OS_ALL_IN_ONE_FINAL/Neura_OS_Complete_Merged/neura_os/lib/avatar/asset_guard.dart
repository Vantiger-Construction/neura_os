import 'package:flutter/services.dart';

/// Utilities to safely probe assets.
///
/// We avoid hard failures when an asset is missing (common during iterative art swaps).
class AssetGuard {
  static Future<bool> exists(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}
