/// Optional cloud backend configuration.
///
/// Values are supplied at build time and are never committed:
///
///   --dart-define=SUPABASE_URL=https://PROJECT.supabase.co
///   --dart-define=SUPABASE_ANON_KEY=PUBLIC_PUBLISHABLE_KEY
///
/// Empty values preserve Neura's local-only boot path. Safe Mode separately
/// prevents cloud initialization even when these values are present.
abstract final class SupabaseConfig {
  static const String url =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Callers must not touch Supabase.instance until this is true and startup
  /// has successfully initialized the optional cloud backend.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
