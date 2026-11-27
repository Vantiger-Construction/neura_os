import 'package:flutter/foundation.dart';

import '../modules/core/app_log.dart';
import '../profiles/local_profile_service.dart';
import '../startup/neura_prefs_cache.dart';
import 'neura_spoken_meaning.dart';

/// Device-local list of the person's confirmed speech corrections
/// ("camera hock" means "Camera Hawk").
///
/// Entries are added only when the person taps "Remember" on a correction
/// they made themselves; nothing is learned from conversation automatically
/// and nothing is copied into companion memory. Profile sessions neither read
/// nor change the list. A data wipe clears it with the other preferences.
class NeuraSpokenLexiconStore {
  NeuraSpokenLexiconStore._();

  static final NeuraSpokenLexiconStore instance = NeuraSpokenLexiconStore._();

  static const _prefsKey = 'neura.voice.spoken_lexicon.v1';

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  NeuraSpokenLexicon _lexicon = NeuraSpokenLexicon();
  bool _loaded = false;

  bool get _available => !LocalProfileService.instance.enabled;

  /// False in profile sessions, where corrections are neither offered nor kept.
  bool get canLearn => _available;

  List<NeuraSpokenCorrection> get entries =>
      _available ? _lexicon.entries : const [];

  void _ensureLoaded() {
    if (_loaded) return;
    try {
      _lexicon = NeuraSpokenLexicon.decode(
        NeuraPrefsCache.prefs.getString(_prefsKey),
      );
      _loaded = true;
    } catch (_) {
      // Prefs not ready yet: behave as an empty list and retry later.
    }
  }

  /// Applies confirmed corrections to a fresh transcript.
  String apply(String transcript) {
    if (!_available) return transcript;
    _ensureLoaded();
    return _lexicon.apply(transcript);
  }

  Future<void> remember(NeuraSpokenCorrection correction) async {
    if (!_available) return;
    _ensureLoaded();
    _lexicon.add(correction);
    await _save();
  }

  Future<void> forget(String heard) async {
    if (!_available) return;
    _ensureLoaded();
    if (_lexicon.remove(heard)) await _save();
  }

  Future<void> _save() async {
    revision.value++;
    try {
      await NeuraPrefsCache.prefs.setString(_prefsKey, _lexicon.encode());
    } catch (error, stack) {
      await AppLog.instance.caught('spoken_lexicon_save_failed', error, stack);
    }
  }

  void resetAfterDataWipe() {
    _lexicon = NeuraSpokenLexicon();
    _loaded = false;
    revision.value++;
  }

  @visibleForTesting
  void resetForTest() => resetAfterDataWipe();
}
