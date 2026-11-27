import 'package:flutter/foundation.dart';

import '../modules/core/app_log.dart';
import '../startup/neura_prefs_cache.dart';
import 'neura_language.dart';

/// Which language Neura listens for.
///
/// Null (the default) is "Automatic": a recognizer that identifies languages
/// (the offline multilingual model) detects each phrase, and the others use
/// their installed default. Choosing a language asks every recognizer for
/// exactly that language; a recognizer without it reports unavailable rather
/// than silently listening in another one.
///
/// Replies follow the language the person speaks or types, whatever this is
/// set to. The preference holds no conversation content.
class NeuraLanguagePrefs {
  NeuraLanguagePrefs._();

  static final NeuraLanguagePrefs instance = NeuraLanguagePrefs._();

  static const _listeningKey = 'neura.voice.listening_language.v1';

  final ValueNotifier<NeuraLanguage?> listening =
      ValueNotifier<NeuraLanguage?>(null);
  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) return;
    final prefs = NeuraPrefsCache.prefsOrNull;
    if (prefs == null) return;
    _loaded = true;
    listening.value = NeuraLanguage.fromCode(prefs.getString(_listeningKey));
  }

  /// The language recognizers should listen for, or null for automatic.
  NeuraLanguage? get listeningLanguage {
    _ensureLoaded();
    return listening.value;
  }

  /// The code passed to native recognizers, or null for automatic.
  String? get listeningCode => listeningLanguage?.code;

  Future<void> setListeningLanguage(NeuraLanguage? language) async {
    _loaded = true;
    listening.value = language;
    try {
      final prefs = NeuraPrefsCache.prefs;
      if (language == null) {
        await prefs.remove(_listeningKey);
      } else {
        await prefs.setString(_listeningKey, language.code);
      }
    } catch (error, stack) {
      await AppLog.instance.caught('language_prefs_save_failed', error, stack);
    }
  }

  void resetAfterDataWipe() {
    _loaded = false;
    listening.value = null;
  }
}
