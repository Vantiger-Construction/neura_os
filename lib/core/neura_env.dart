// neura_env.dart — environment config, beta flag, platform gates
// Drop into: lib/core/neura_env.dart

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time configuration.
///
/// Supply real values at build time (never commit them):
///   flutter build windows --release ^
///     --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co ^
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
class NeuraEnv {
  NeuraEnv._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// URL of the deployed `verify-purchase` Supabase Edge Function (see
  /// supabase/functions/verify-purchase/index.ts), used by
  /// WindowsLicenseService to confirm a Stripe purchase. Not secret --
  /// safe to bake into the build via --dart-define like the values above.
  /// Deliberately NOT read from SupabaseConfig / the supabase_flutter SDK:
  /// this is called over plain HTTP so enabling it never triggers
  /// Supabase.initialize() or the auth-gated boot path.
  static const String verifyPurchaseUrl =
      String.fromEnvironment('VERIFY_PURCHASE_URL', defaultValue: '');
}

/// Beta gating. IAP / purchases must be gated behind this.
/// Beta builds pass --dart-define=BETA_MODE=true
const bool kBetaMode = bool.fromEnvironment('BETA_MODE', defaultValue: true);

/// True only when in-app purchases should be reachable.
/// In beta this is always false.
bool get kIapEnabled => !kBetaMode;

/// Platform gates.
class NeuraPlatform {
  NeuraPlatform._();

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Biometric auth is Android-only in phase 1.
  /// Every biometric call site must check this first:
  ///   if (!NeuraPlatform.biometricsSupported) return true; // pass-through
  static bool get biometricsSupported => isAndroid;
}
