abstract final class SupabaseConfig {
  // Get these from https://supabase.com/dashboard/project/_/settings/api
  // Project URL → "Project URL"   |   API Keys → "anon" / "public" key
  static const String url = 'YOUR_SUPABASE_PROJECT_URL';
  static const String anonKey =
      'YOUR_SUPABASE_ANON_KEY'; // passed as publishableKey

  /// False while these are still the placeholder values above — callers must
  /// not touch Supabase.instance (auth included) until this is true, since
  /// Supabase.initialize() is skipped entirely in that case.
  static bool get isConfigured =>
      !url.startsWith('YOUR_') && !anonKey.startsWith('YOUR_');
}
