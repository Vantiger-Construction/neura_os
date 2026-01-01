import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';
import 'human_prefs.dart';

class HumanPrefsController {
  HumanPrefsController._();
  static final HumanPrefsController instance = HumanPrefsController._();

  static const _key = 'neura.human.prefs.v1';

  final ValueNotifier<HumanPrefs> prefs = ValueNotifier<HumanPrefs>(HumanPrefs.defaults);

  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
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
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, next.toJsonString());
    } catch (e) {
      await AppLog.instance.warn('HumanPrefsController.update failed: $e');
    }
  }
}
