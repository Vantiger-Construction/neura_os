import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../modules/core/app_log.dart';
import '../../startup/neura_prefs_cache.dart';

enum NeuraCompanionMotion { still, subtle, expressive }

enum NeuraCompanionScale { compact, standard, large }

extension NeuraCompanionScaleValue on NeuraCompanionScale {
  double get factor => switch (this) {
        NeuraCompanionScale.compact => 0.84,
        NeuraCompanionScale.standard => 1.0,
        NeuraCompanionScale.large => 1.14,
      };
}

class ShellPrefs {
  final bool ambientFx;
  final bool portalFx;
  final bool walkingShimmer;
  final NeuraCompanionMotion companionMotion;
  final NeuraCompanionScale companionScale;
  final bool roomActivityHints;

  const ShellPrefs({
    required this.ambientFx,
    required this.portalFx,
    required this.walkingShimmer,
    this.companionMotion = NeuraCompanionMotion.subtle,
    this.companionScale = NeuraCompanionScale.standard,
    this.roomActivityHints = true,
  });

  ShellPrefs copyWith({
    bool? ambientFx,
    bool? portalFx,
    bool? walkingShimmer,
    NeuraCompanionMotion? companionMotion,
    NeuraCompanionScale? companionScale,
    bool? roomActivityHints,
  }) {
    return ShellPrefs(
      ambientFx: ambientFx ?? this.ambientFx,
      portalFx: portalFx ?? this.portalFx,
      walkingShimmer: walkingShimmer ?? this.walkingShimmer,
      companionMotion: companionMotion ?? this.companionMotion,
      companionScale: companionScale ?? this.companionScale,
      roomActivityHints: roomActivityHints ?? this.roomActivityHints,
    );
  }

  Map<String, dynamic> toJson() => {
        'ambientFx': ambientFx,
        'portalFx': portalFx,
        'walkingShimmer': walkingShimmer,
        'companionMotion': companionMotion.name,
        'companionScale': companionScale.name,
        'roomActivityHints': roomActivityHints,
      };

  static ShellPrefs fromJson(Map<String, dynamic> json) {
    return ShellPrefs(
      ambientFx: (json['ambientFx'] as bool?) ?? true,
      portalFx: (json['portalFx'] as bool?) ?? true,
      walkingShimmer: (json['walkingShimmer'] as bool?) ?? true,
      companionMotion: NeuraCompanionMotion.values.firstWhere(
        (value) => value.name == json['companionMotion'],
        orElse: () => NeuraCompanionMotion.subtle,
      ),
      companionScale: NeuraCompanionScale.values.firstWhere(
        (value) => value.name == json['companionScale'],
        orElse: () => NeuraCompanionScale.standard,
      ),
      roomActivityHints: (json['roomActivityHints'] as bool?) ?? true,
    );
  }

  static const defaults = ShellPrefs(
    ambientFx: true,
    portalFx: true,
    walkingShimmer: true,
  );
}

class ShellPrefsController {
  ShellPrefsController._();

  static final ShellPrefsController instance = ShellPrefsController._();

  static const _prefsKey = 'neura.shell.prefs.v1';

  final ValueNotifier<ShellPrefs> prefs = ValueNotifier<ShellPrefs>(
    ShellPrefs.defaults,
  );

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
