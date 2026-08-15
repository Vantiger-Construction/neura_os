import 'package:flutter/foundation.dart';

import '../modules/core/app_log.dart';
import '../startup/neura_prefs_cache.dart';

/// Whether Neura should listen for speech and record short encrypted
/// clips automatically, without a manual chat turn.
///
/// Off by default -- opt-in, not opt-out. Continuous voice-activity-
/// triggered recording can capture bystanders who never consented to it,
/// which is illegal wiretapping in two-party-consent jurisdictions unless
/// everyone present has agreed -- this must never silently turn on.
class AmbientListeningPrefsController {
  AmbientListeningPrefsController._();

  static final AmbientListeningPrefsController instance =
      AmbientListeningPrefsController._();

  static const _prefsKey = 'neura.ambient.listening.enabled.v1';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  Future<void> init() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      enabled.value = sp.getBool(_prefsKey) ?? false;
    } catch (e, st) {
      await AppLog.instance.caught('ambient_prefs_init_failed', e, st);
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.setBool(_prefsKey, value);
    } catch (e, st) {
      await AppLog.instance.caught('ambient_prefs_update_failed', e, st);
    }
  }

  void resetAfterDataWipe() {
    enabled.value = false;
  }
}
