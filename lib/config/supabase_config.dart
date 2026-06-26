abstract final class SupabaseConfig {
  // Get these from https://supabase.com/dashboard/project/_/settings/api
  // Project URL → "Project URL"   |   API Keys → "anon" / "public" key
  static const String url = 'YOUR_SUPABASE_PROJECT_URL';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY'; // passed as publishableKey
}
