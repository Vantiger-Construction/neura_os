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
    } catch (e) {
      await AppLog.instance.warn('HumanPrefsController.init failed: $e');
    }
  }

  Future<void> update(HumanPrefs next) async {
    prefs.value = next;
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.setString(_key, next.toJsonString());
    } catch (e) {
      await AppLog.instance.warn('HumanPrefsController.update failed: $e');
    }
  }

  void resetAfterDataWipe() {
    prefs.value = HumanPrefs.defaults;
  }
}
