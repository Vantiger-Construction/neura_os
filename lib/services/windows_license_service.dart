import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/neura_env.dart';
import '../startup/neura_prefs_cache.dart';

/// Windows-native premium entitlement -- separate from BillingService (which
/// wraps the in_app_purchase plugin and only works through Google Play/Apple
/// StoreKit, not on Windows). A purchase happens via a Stripe Payment Link
/// opened in the system browser; the "code" the user pastes back into the
/// app afterward is the Stripe Checkout session id itself, verified live
/// against supabase/functions/verify-purchase/index.ts over plain HTTP (no
/// supabase_flutter SDK involved, so this never touches Supabase.initialize()
/// or the auth-gated boot path).
class WindowsLicenseService {
  WindowsLicenseService._();
  static final WindowsLicenseService instance = WindowsLicenseService._();

  static const _kIsPremiumKey = 'windows_license.is_premium';
  static const _kSessionIdKey = 'windows_license.session_id';

  bool get isPremium =>
      NeuraPrefsCache.prefsOrNull?.getBool(_kIsPremiumKey) ?? false;

  /// Verifies [sessionId] against the deployed Edge Function. On success,
  /// persists the unlocked state locally so isPremium survives restarts
  /// without needing to re-verify online every launch.
  Future<bool> redeemCode(String sessionId) async {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty || NeuraEnv.verifyPurchaseUrl.isEmpty) return false;

    try {
      final uri = Uri.parse(NeuraEnv.verifyPurchaseUrl)
          .replace(queryParameters: {'session_id': trimmed});
      final response = await http.get(
        uri,
        headers: {'accept': 'application/json'},
      );
      if (response.statusCode != 200) return false;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final valid = body['valid'] == true;
      if (!valid) return false;

      final prefs = NeuraPrefsCache.prefs;
      await prefs.setBool(_kIsPremiumKey, true);
      await prefs.setString(_kSessionIdKey, trimmed);
      return true;
    } catch (_) {
      return false;
    }
  }
}
