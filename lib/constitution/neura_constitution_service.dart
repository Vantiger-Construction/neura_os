import 'dart:convert';

import '../startup/neura_prefs_cache.dart';
import 'neura_personal_constitution.dart';

/// Shared, standalone persistence for [NeuraPersonalConstitution], read by
/// the Autonomy Kernel and the cloud model router.
///
/// Adaptive Intent historically embedded the same settings in its own
/// snapshot. [load] imports that value once when this store has no value yet,
/// preserving an existing explicit boundary without adopting the snapshot's
/// separate signal-freshness contract.
class NeuraConstitutionService {
  NeuraConstitutionService._();

  static final NeuraConstitutionService instance = NeuraConstitutionService._();

  static const _key = 'neura.constitution.v1';
  static const _legacyAdaptiveIntentKey = 'neura.adaptive_intent.state.v1';

  NeuraPersonalConstitution _current = const NeuraPersonalConstitution();
  bool _loaded = false;

  /// The current constitution. Safe to read synchronously and before
  /// [load] completes -- callers get the default constitution until a saved
  /// one is loaded, never an error or a stale platform-channel wait.
  NeuraPersonalConstitution get current => _current;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = NeuraPrefsCache.prefsOrNull;
    if (prefs == null) {
      throw StateError(
        'Personal constitution is unavailable before preferences initialize.',
      );
    }

    final raw = prefs.getString(_key);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _current = _fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // A damaged persisted boundary must not silently turn cloud AI on.
        _current = const NeuraPersonalConstitution(allowCloudAi: false);
      }
    } else {
      final legacyRaw = prefs.getString(_legacyAdaptiveIntentKey);
      final migrated = _fromLegacyAdaptiveIntent(legacyRaw);
      if (migrated != null) {
        _current = migrated;
        try {
          await prefs.setString(_key, jsonEncode(_toJson(migrated)));
        } catch (_) {
          // The migrated in-memory boundary still applies for this session.
        }
      }
    }
    _loaded = true;
  }

  Future<void> save(NeuraPersonalConstitution value) async {
    final normalized = value.normalized();
    _current = normalized;
    try {
      await NeuraPrefsCache.prefs
          .setString(_key, jsonEncode(_toJson(normalized)));
    } catch (_) {
      // The in-memory value above still applies for this session.
    }
    _loaded = true;
  }

  void resetAfterDataWipe() {
    _current = const NeuraPersonalConstitution();
    _loaded = false;
  }

  static Map<String, dynamic> _toJson(NeuraPersonalConstitution value) => {
        'allow_cloud_ai': value.allowCloudAi,
        'allow_external_messages': value.allowExternalMessages,
        'allow_purchases': value.allowPurchases,
        'allow_calendar_writes': value.allowCalendarWrites,
        'keep_sensitive_content_local': value.keepSensitiveContentLocal,
        'require_external_preview': value.requireExternalPreview,
        'work_hours_start': value.workHoursStart,
        'work_hours_end': value.workHoursEnd,
      };

  static NeuraPersonalConstitution _fromJson(Map<String, dynamic> json) {
    const defaults = NeuraPersonalConstitution();
    int boundedInt(String key, int fallback) {
      final value = json[key];
      return (value is num ? value.toInt() : fallback).clamp(0, 23).toInt();
    }

    return NeuraPersonalConstitution(
      allowCloudAi: json['allow_cloud_ai'] as bool? ?? defaults.allowCloudAi,
      allowExternalMessages: json['allow_external_messages'] as bool? ??
          defaults.allowExternalMessages,
      allowPurchases:
          json['allow_purchases'] as bool? ?? defaults.allowPurchases,
      allowCalendarWrites: json['allow_calendar_writes'] as bool? ??
          defaults.allowCalendarWrites,
      keepSensitiveContentLocal:
          json['keep_sensitive_content_local'] as bool? ??
              defaults.keepSensitiveContentLocal,
      requireExternalPreview: json['require_external_preview'] as bool? ??
          defaults.requireExternalPreview,
      workHoursStart: boundedInt('work_hours_start', defaults.workHoursStart),
      workHoursEnd: boundedInt('work_hours_end', defaults.workHoursEnd),
    ).normalized();
  }

  static NeuraPersonalConstitution? _fromLegacyAdaptiveIntent(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final constitution = decoded['constitution'];
      if (constitution is! Map || constitution['allow_cloud_ai'] is! bool) {
        return null;
      }
      return _fromJson(Map<String, dynamic>.from(constitution));
    } catch (_) {
      return null;
    }
  }
}
