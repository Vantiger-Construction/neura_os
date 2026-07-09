import 'goodwill_models.dart';
import '../../startup/neura_prefs_cache.dart';

class GoodwillStore {
  GoodwillStore._();
  static final GoodwillStore instance = GoodwillStore._();

  static const _key = 'neura_kindness_acts_v1';

  Future<List<KindnessAct>> getAll() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key) ?? '';
    return KindnessAct.decodeList(raw);
  }

  Future<void> setAll(List<KindnessAct> acts) async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_key, KindnessAct.encodeList(acts));
  }

  Future<void> wipe() async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.remove(_key);
  }
}
