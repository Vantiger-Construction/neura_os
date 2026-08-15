import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../modules/core/app_log.dart';
import 'focus_mode.dart';
import '../../../startup/neura_prefs_cache.dart';

class FocusState {
  final FocusMode mode;
  final DateTime startedAt;

  const FocusState({required this.mode, required this.startedAt});

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'startedAt': startedAt.toIso8601String(),
      };

  static FocusState fromJson(Map<String, dynamic> json) {
    final modeName = (json['mode'] as String?) ?? 'off';
    final mode = FocusMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => FocusMode.off,
    );
    final startedAtRaw =
        (json['startedAt'] as String?) ?? DateTime.now().toIso8601String();
    return FocusState(
        mode: mode,
        startedAt: DateTime.tryParse(startedAtRaw) ?? DateTime.now());
  }
}

/// Global Focus Mode controller.
///
/// - Persists to SharedPreferences
/// - Exposes a ValueNotifier so the shell can react (banner, accents, etc.)
class FocusController {
  FocusController._();

  static final FocusController instance = FocusController._();

  static const _prefsKey = 'neura.focus.state.v1';

  final ValueNotifier<FocusState> state = ValueNotifier<FocusState>(
    FocusState(mode: FocusMode.off, startedAt: DateTime.now()),
  );

  Future<void> init() async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        state.value = FocusState.fromJson(decoded);
      }
    } catch (e, st) {
      await AppLog.instance.caught('focus_controller_init_failed', e, st);
    }
  }

  Future<void> setMode(FocusMode mode) async {
    final next = FocusState(mode: mode, startedAt: DateTime.now());
    state.value = next;
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
    } catch (e, st) {
      await AppLog.instance.caught('focus_controller_update_failed', e, st);
    }
  }

  void resetAfterDataWipe() {
    state.value = FocusState(mode: FocusMode.off, startedAt: DateTime.now());
  }
}
