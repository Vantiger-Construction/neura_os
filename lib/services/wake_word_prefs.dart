import 'package:flutter/foundation.dart';

import '../modules/core/app_log.dart';
import '../startup/neura_prefs_cache.dart';

/// Whether Neura should continuously listen for the "Hey Neura" wake phrase
/// and start a hands-free chat turn when heard.
///
/// Off by default -- opt-in, not opt-out, same posture as
/// [AmbientListeningPrefsController]. Distinct toggle/pref key on purpose:
/// this is continuous *speech-to-text* (produces transcribed text sent to an
/// LLM once a wake phrase is heard), a different privacy model from ambient
/// listening's raw-audio voice-activity capture -- a user opting into one
/// should not silently opt into the other.
class WakeWordPrefsController {
  WakeWordPrefsController._();

  static final WakeWordPrefsController instance = WakeWordPrefsController._();

  static const _prefsKey = 'neura.wake_word.enabled.v1';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  Future<void> init() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      enabled.value = sp.getBool(_prefsKey) ?? false;
    } catch (e, st) {
      await AppLog.instance.caught('wake_word_prefs_init_failed', e, st);
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.setBool(_prefsKey, value);
    } catch (e, st) {
      await AppLog.instance.caught('wake_word_prefs_update_failed', e, st);
    }
  }

  void resetAfterDataWipe() {
    enabled.value = false;
  }
}
