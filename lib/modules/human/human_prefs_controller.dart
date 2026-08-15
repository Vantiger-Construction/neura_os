import 'package:flutter/foundation.dart';
import '../core/app_log.dart';
import 'human_prefs.dart';
import '../../startup/neura_prefs_cache.dart';

class HumanPrefsController {
  HumanPrefsController._();
  static final HumanPrefsController instance = HumanPrefsController._();

  static const _key = 'neura.human.prefs.v1';

  final ValueNotifier<HumanPrefs> prefs = ValueNotifier<HumanPrefs>(HumanPrefs.defaults);

  Future<void> init() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      final raw = sp.getString(_key);
      if (raw == null || raw.trim().isEmpty) return;
      prefs.value = HumanPrefs.fromJsonString(raw);
    } catch (e, st) {
      await AppLog.instance.caught('human_prefs_init_failed', e, st);
    }
  }

  Future<void> update(HumanPrefs next) async {
    prefs.value = next;
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.setString(_key, next.toJsonString());
    } catch (e, st) {
      await AppLog.instance.caught('human_prefs_update_failed', e, st);
    }
  }

  void resetAfterDataWipe() {
    prefs.value = HumanPrefs.defaults;
  }
}
