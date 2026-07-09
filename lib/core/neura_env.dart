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
}

/// Beta gating. IAP / purchases must be gated behind this.
/// Beta builds pass --dart-define=BETA_MODE=true
const bool kBetaMode =
    bool.fromEnvironment('BETA_MODE', defaultValue: true);

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
