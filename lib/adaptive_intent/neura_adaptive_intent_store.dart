import 'dart:convert';

import '../cognitive/neura_cognitive_state.dart';
import '../constitution/neura_personal_constitution.dart';
import '../startup/neura_prefs_cache.dart';

class NeuraAdaptiveIntentSnapshot {
  const NeuraAdaptiveIntentSnapshot({
    required this.signals,
    required this.constitution,
    required this.savedAt,
  });

  final NeuraCognitiveSignals signals;
  final NeuraPersonalConstitution constitution;
  final DateTime savedAt;

  bool hasFreshSignalsAt(
    DateTime now, {
    Duration maxAge = const Duration(hours: 12),
  }) {
    final utcNow = now.toUtc();
    final utcSavedAt = savedAt.toUtc();
    if (utcSavedAt.isAfter(utcNow.add(const Duration(minutes: 5)))) {
      return false;
    }
    return utcNow.difference(utcSavedAt) <= maxAge;
  }

  Map<String, Object?> toJson() => {
    'v': 1,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'signals': {
      'energy': signals.energy,
      'focus': signals.focus,
      'cognitive_load': signals.cognitiveLoad,
      'urgency': signals.urgency,
      'task_switch_rate': signals.taskSwitchRate,
      'completion_rate': signals.completionRate,
      'notification_pressure': signals.notificationPressure,
      'evidence_count': signals.evidenceCount,
      'includes_self_report': signals.includesSelfReport,
    },
    'constitution': {
      'allow_cloud_ai': constitution.allowCloudAi,
      'allow_external_messages': constitution.allowExternalMessages,
      'allow_purchases': constitution.allowPurchases,
      'allow_calendar_writes': constitution.allowCalendarWrites,
      'keep_sensitive_content_local': constitution.keepSensitiveContentLocal,
      'require_external_preview': constitution.requireExternalPreview,
      'work_hours_start': constitution.workHoursStart,
      'work_hours_end': constitution.workHoursEnd,
    },
  };

  factory NeuraAdaptiveIntentSnapshot.fromJson(Map<String, Object?> json) {
    final rawSignals = json['signals'];
    final signalJson = rawSignals is Map
        ? Map<String, Object?>.from(rawSignals)
        : const <String, Object?>{};
    final rawConstitution = json['constitution'];
    final constitutionJson = rawConstitution is Map
        ? Map<String, Object?>.from(rawConstitution)
        : const <String, Object?>{};

    double unit(String key, double fallback) {
      final value = signalJson[key];
      return (value is num ? value.toDouble() : fallback)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    int boundedInt(
      Map<String, Object?> source,
      String key,
      int fallback,
      int min,
      int max,
    ) {
      final value = source[key];
      return (value is num ? value.toInt() : fallback).clamp(min, max).toInt();
    }

    final defaults = NeuraCognitiveSignals.defaults();
    return NeuraAdaptiveIntentSnapshot(
      signals: NeuraCognitiveSignals(
        energy: unit('energy', defaults.energy),
        focus: unit('focus', defaults.focus),
        cognitiveLoad: unit('cognitive_load', defaults.cognitiveLoad),
        urgency: unit('urgency', defaults.urgency),
        taskSwitchRate: unit('task_switch_rate', defaults.taskSwitchRate),
        completionRate: unit('completion_rate', defaults.completionRate),
        notificationPressure: unit(
          'notification_pressure',
          defaults.notificationPressure,
        ),
        evidenceCount: boundedInt(
          signalJson,
          'evidence_count',
          defaults.evidenceCount,
          0,
          20,
        ),
        includesSelfReport: signalJson['includes_self_report'] != false,
      ),
      constitution: NeuraPersonalConstitution(
        allowCloudAi: constitutionJson['allow_cloud_ai'] == true,
        allowExternalMessages:
            constitutionJson['allow_external_messages'] == true,
        allowPurchases: constitutionJson['allow_purchases'] == true,
        allowCalendarWrites: constitutionJson['allow_calendar_writes'] != false,
        keepSensitiveContentLocal:
            constitutionJson['keep_sensitive_content_local'] != false,
        requireExternalPreview:
            constitutionJson['require_external_preview'] != false,
        workHoursStart: boundedInt(
          constitutionJson,
          'work_hours_start',
          7,
          0,
          23,
        ),
        workHoursEnd: boundedInt(constitutionJson, 'work_hours_end', 20, 0, 23),
      ),
      savedAt:
          DateTime.tryParse(json['saved_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

abstract interface class NeuraAdaptiveIntentStore {
  Future<NeuraAdaptiveIntentSnapshot?> load();

  Future<void> save(NeuraAdaptiveIntentSnapshot snapshot);

  Future<void> clear();
}

class NeuraPrefsAdaptiveIntentStore implements NeuraAdaptiveIntentStore {
  const NeuraPrefsAdaptiveIntentStore();

  static const stateKey = 'neura.adaptive_intent.state.v1';

  @override
  Future<NeuraAdaptiveIntentSnapshot?> load() async {
    final raw = NeuraPrefsCache.prefs.getString(stateKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return NeuraAdaptiveIntentSnapshot.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      // Corrupt or pre-release state must not prevent Neura from starting.
      return null;
    }
  }

  @override
  Future<void> save(NeuraAdaptiveIntentSnapshot snapshot) async {
    final written = await NeuraPrefsCache.prefs.setString(
      stateKey,
      jsonEncode(snapshot.toJson()),
    );
    if (!written) {
      throw StateError('Adaptive Intent settings could not be saved.');
    }
  }

  @override
  Future<void> clear() async {
    await NeuraPrefsCache.prefs.remove(stateKey);
  }
}
