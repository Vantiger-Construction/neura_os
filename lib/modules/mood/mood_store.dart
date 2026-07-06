import 'mood_models.dart';
import '../../startup/neura_prefs_cache.dart';

class MoodStore {
  MoodStore._();
  static final MoodStore instance = MoodStore._();

  static const _key = 'neura_mood_entries_v1';

  Future<List<MoodEntry>> getAll() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key) ?? '';
    return MoodEntry.decodeList(raw);
  }

  Future<void> add(MoodEntry entry) async {
    final items = await getAll();
    items.add(entry);
    // keep recent-ish size bounded
    if (items.length > 2000) {
      items.removeRange(0, items.length - 2000);
    }
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_key, MoodEntry.encodeList(items));
  }

  Future<MoodEntry?> latest() async {
    final items = await getAll();
    if (items.isEmpty) return null;
    return items.last;
  }
}
