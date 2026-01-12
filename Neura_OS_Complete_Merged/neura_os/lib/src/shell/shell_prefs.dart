import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/core/app_log.dart';

class ShellPrefs {
  final bool ambientFx;
  final bool portalFx;
  final bool walkingShimmer;

  const ShellPrefs({required this.ambientFx, required this.portalFx, required this.walkingShimmer});

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

  static const defaults = ShellPrefs(ambientFx: true, portalFx: true, walkingShimmer: true);
}

class ShellPrefsController {
  ShellPrefsController._();

  static final ShellPrefsController instance = ShellPrefsController._();

  static const _prefsKey = 'neura.shell.prefs.v1';

  final ValueNotifier<ShellPrefs> prefs = ValueNotifier<ShellPrefs>(ShellPrefs.defaults);

  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        prefs.value = ShellPrefs.fromJson(decoded);
      }
    } catch (e) {
      await AppLog.instance.warn('ShellPrefsController.init failed: $e');
    }
  }

  Future<void> update(ShellPrefs next) async {
    prefs.value = next;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, jsonEncode(next.toJson()));
    } catch (e) {
      await AppLog.instance.warn('ShellPrefsController.update failed: $e');
    }
  }
}
