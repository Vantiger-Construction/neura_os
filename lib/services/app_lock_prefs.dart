import 'package:flutter/foundation.dart';

import '../modules/core/app_log.dart';
import '../startup/neura_prefs_cache.dart';

/// Whether Neura should require device authentication (biometrics or
/// PIN/password) before showing the dashboard.
///
/// Off by default — this is opt-in so existing local-only installs never
/// get locked out by a change they didn't ask for. Only meaningful when
/// Supabase is unconfigured (the sign-in screen already gates identity
/// once real Supabase keys are set — see [SupabaseConfig.isConfigured]).
class AppLockPrefsController {
  AppLockPrefsController._();

  static final AppLockPrefsController instance = AppLockPrefsController._();

  static const _prefsKey = 'neura.security.applock.v1';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  Future<void> init() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      enabled.value = sp.getBool(_prefsKey) ?? false;
    } catch (e, st) {
      await AppLog.instance.caught('app_lock_prefs_init_failed', e, st);
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.setBool(_prefsKey, value);
    } catch (e, st) {
      await AppLog.instance.caught('app_lock_prefs_update_failed', e, st);
    }
  }

  void resetAfterDataWipe() {
    enabled.value = false;
  }
}
