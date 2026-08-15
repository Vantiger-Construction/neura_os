import '../models/neura_audience.dart';
import '../../startup/neura_prefs_cache.dart';

class NeuraAudienceService {
  NeuraAudienceService._internal();
  static final NeuraAudienceService instance = NeuraAudienceService._internal();

  static const _keyAudience = 'neura_audience';

  NeuraAudience _currentAudience = NeuraAudience.adult;
  bool _loaded = false;

  NeuraAudience get currentAudience => _currentAudience;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = NeuraPrefsCache.prefs;
    final label = prefs.getString(_keyAudience);
    if (label != null) {
      _currentAudience = _parse(label);
    }
    _loaded = true;
  }

  Future<void> setAudience(NeuraAudience audience) async {
    _currentAudience = audience;
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_keyAudience, audience.label);
  }

  void resetAfterDataWipe() {
    _currentAudience = NeuraAudience.adult;
    _loaded = false;
  }

  NeuraAudience _parse(String label) {
    switch (label) {
      case 'child':
        return NeuraAudience.child;
      case 'teen':
        return NeuraAudience.teen;
      case 'adult':
      default:
        return NeuraAudience.adult;
    }
  }
}
