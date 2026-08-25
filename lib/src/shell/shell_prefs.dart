import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../modules/core/app_log.dart';
import '../../startup/neura_prefs_cache.dart';

class ShellPrefs {
  final bool ambientFx;
  final bool portalFx;
  final bool walkingShimmer;

  const ShellPrefs(
      {required this.ambientFx,
      required this.portalFx,
      required this.walkingShimmer});

  ShellPrefs copyWith({bool? ambientFx, bool? portalFx, bool? walkingShimmer}) {
    return ShellPrefs(
      ambientFx: ambientFx ?? this.ambientFx,
      portalFx: portalFx ?? this.portalFx,
      walkingShimmer: walkingShimmer ?? this.walkingShimmer,
    );
  }

  Map<String, dynamic> toJson() => {
        'ambientFx': ambientFx,
        'portalFx': portalFx,
        'walkingShimmer': walkingShimmer,
      };

  static ShellPrefs fromJson(Map<String, dynamic> json) {
    return ShellPrefs(
      ambientFx: (json['ambientFx'] as bool?) ?? true,
      portalFx: (json['portalFx'] as bool?) ?? true,
      walkingShimmer: (json['walkingShimmer'] as bool?) ?? true,
    );
  }

  static const defaults =
      ShellPrefs(ambientFx: true, portalFx: true, walkingShimmer: true);
}

class ShellPrefsController {
  ShellPrefsController._();

  static final ShellPrefsController instance = ShellPrefsController._();

  static const _prefsKey = 'neura.shell.prefs.v1';

  final ValueNotifier<ShellPrefs> prefs =
      ValueNotifier<ShellPrefs>(ShellPrefs.defaults);

  Future<void> init() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      final raw = sp.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        prefs.value = ShellPrefs.fromJson(decoded);
      }
    } catch (e, st) {
      await AppLog.instance.caught('shell_prefs_init_failed', e, st);
    }
  }

  Future<void> update(ShellPrefs next) async {
    prefs.value = next;
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.setString(_prefsKey, jsonEncode(next.toJson()));
    } catch (e, st) {
      await AppLog.instance.caught('shell_prefs_update_failed', e, st);
    }
  }
}
