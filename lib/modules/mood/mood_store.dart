import 'mood_models.dart';
import '../../core/memory/memory_crypto.dart';
import '../../startup/neura_prefs_cache.dart';

/// Local mood history, encrypted at rest (reuses the same per-install key
/// as [MemoryCrypto]'s other callers). Previously stored as a plain JSON
/// string via SharedPreferences - mood entries are as sensitive as
/// anything else on-device, so this brings them in line with the memory
/// graph and therapy journal.
class MoodStore {
  MoodStore._();
  static final MoodStore instance = MoodStore._();

  static const _key = 'neura_mood_entries_v1';

  MemoryCrypto? _crypto;
  Future<MemoryCrypto> _ensureCrypto() async {
    _crypto ??= await MemoryCrypto.demo();
    return _crypto!;
  }

  Future<List<MoodEntry>> getAll() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key) ?? '';
    if (raw.trim().isEmpty) return <MoodEntry>[];

    final crypto = await _ensureCrypto();
    try {
      final decrypted = await crypto.decryptJson(raw);
      final items = (decrypted['items'] as List)
          .whereType<Map>()
          .map((m) => MoodEntry.fromJson(Map<String, Object?>.from(m)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return items;
    } catch (_) {
      // Not a valid encrypted blob - likely legacy plaintext from before
      // mood data was encrypted. Migrate transparently rather than losing
      // existing history: read it the old way, then re-save encrypted so
      // it's fixed going forward.
      final legacy = MoodEntry.decodeList(raw);
      if (legacy.isNotEmpty) {
        await _persist(legacy);
      }
      return legacy;
    }
  }

  Future<void> add(MoodEntry entry) async {
    final items = await getAll();
    items.add(entry);
    // keep recent-ish size bounded
    if (items.length > 2000) {
      items.removeRange(0, items.length - 2000);
    }
    await _persist(items);
  }

  Future<void> _persist(List<MoodEntry> items) async {
    final crypto = await _ensureCrypto();
    final blob = await crypto.encryptJson({'items': items.map((e) => e.toJson()).toList()});
    await NeuraPrefsCache.prefs.setString(_key, blob);
  }

  Future<MoodEntry?> latest() async {
    final items = await getAll();
    if (items.isEmpty) return null;
    return items.last;
  }
}
