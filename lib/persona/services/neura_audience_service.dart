import 'package:shared_preferences/shared_preferences.dart';

import '../models/neura_audience.dart';

class NeuraAudienceService {
  NeuraAudienceService._internal();
  static final NeuraAudienceService instance = NeuraAudienceService._internal();

  static const _keyAudience = 'neura_audience';

  NeuraAudience _currentAudience = NeuraAudience.adult;
  bool _loaded = false;

  NeuraAudience get currentAudience => _currentAudience;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final label = prefs.getString(_keyAudience);
    if (label != null) {
      _currentAudience = _parse(label);
    }
    _loaded = true;
  }

  Future<void> setAudience(NeuraAudience audience) async {
    _currentAudience = audience;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudience, audience.label);
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
