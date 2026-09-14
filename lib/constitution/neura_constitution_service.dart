import 'dart:convert';

import '../startup/neura_prefs_cache.dart';
import 'neura_personal_constitution.dart';

/// Shared, standalone persistence for [NeuraPersonalConstitution], read by
/// the Autonomy Kernel and the cloud model router.
///
/// This is deliberately separate from Adaptive Intent's own embedded copy
/// (`NeuraAdaptiveIntentSnapshot.constitution`), which remains untouched by
/// this service. The two are not synced yet -- a constitution edited from
/// the Adaptive Intent screen does not currently reach this service, and
/// vice versa. Pointing one at the other is a follow-up, not done here,
/// since Adaptive Intent's snapshot has its own freshness/versioning
/// contract this service should not disturb blind.
class NeuraConstitutionService {
  NeuraConstitutionService._();

  static final NeuraConstitutionService instance = NeuraConstitutionService._();

  static const _key = 'neura.constitution.v1';

  NeuraPersonalConstitution _current = const NeuraPersonalConstitution();
  bool _loaded = false;

  /// The current constitution. Safe to read synchronously and before
  /// [load] completes -- callers get the default constitution until a saved
  /// one is loaded, never an error or a stale platform-channel wait.
  NeuraPersonalConstitution get current => _current;

  Future<void> load() async {
    if (_loaded) return;
    final raw = NeuraPrefsCache.prefsOrNull?.getString(_key);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _current = _fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Self-heal: corrupted JSON -> keep the default constitution.
        _current = const NeuraPersonalConstitution();
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
}
