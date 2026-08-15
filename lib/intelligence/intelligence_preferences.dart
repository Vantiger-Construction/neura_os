import 'models.dart';

class NeuraIntelligencePreferences {
  const NeuraIntelligencePreferences({
    this.enabled = true,
    this.allowSensitiveSignals = false,
    this.showDecisionReasons = true,
    this.maxDailySuggestions = 3,
    this.quietHoursEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 7,
    this.pausedUntil,
  });

  final bool enabled;
  final bool allowSensitiveSignals;
  final bool showDecisionReasons;
  final int maxDailySuggestions;
  final bool quietHoursEnabled;
  final int quietHoursStart;
  final int quietHoursEnd;
  final DateTime? pausedUntil;

  bool isQuietAt(DateTime now) {
    if (pausedUntil != null && now.isBefore(pausedUntil!)) return true;
    if (!quietHoursEnabled) return false;
    if (quietHoursStart == quietHoursEnd) return true;
    if (quietHoursStart < quietHoursEnd) {
      return now.hour >= quietHoursStart && now.hour < quietHoursEnd;
    }
    return now.hour >= quietHoursStart || now.hour < quietHoursEnd;
  }

  NeuraIntelligencePreferences copyWith({
    bool? enabled,
    bool? allowSensitiveSignals,
    bool? showDecisionReasons,
    int? maxDailySuggestions,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
    DateTime? pausedUntil,
    bool clearPause = false,
  }) {
    return NeuraIntelligencePreferences(
      enabled: enabled ?? this.enabled,
      allowSensitiveSignals:
          allowSensitiveSignals ?? this.allowSensitiveSignals,
      showDecisionReasons: showDecisionReasons ?? this.showDecisionReasons,
      maxDailySuggestions:
          (maxDailySuggestions ?? this.maxDailySuggestions).clamp(1, 6).toInt(),
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart:
          (quietHoursStart ?? this.quietHoursStart).clamp(0, 23).toInt(),
      quietHoursEnd:
          (quietHoursEnd ?? this.quietHoursEnd).clamp(0, 23).toInt(),
      pausedUntil: clearPause ? null : pausedUntil ?? this.pausedUntil,
    );
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'enabled': enabled,
        'allow_sensitive_signals': allowSensitiveSignals,
        'show_decision_reasons': showDecisionReasons,
        'max_daily_suggestions': maxDailySuggestions,
        'quiet_hours_enabled': quietHoursEnabled,
        'quiet_hours_start': quietHoursStart,
        'quiet_hours_end': quietHoursEnd,
        'paused_until': pausedUntil?.toUtc().toIso8601String(),
      };

  factory NeuraIntelligencePreferences.fromJson(
    Map<String, Object?> json,
  ) {
    int integer(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    return NeuraIntelligencePreferences(
      enabled: json['enabled'] != false,
      allowSensitiveSignals: json['allow_sensitive_signals'] == true,
      showDecisionReasons: json['show_decision_reasons'] != false,
      maxDailySuggestions:
          integer('max_daily_suggestions', 3).clamp(1, 6).toInt(),
      quietHoursEnabled: json['quiet_hours_enabled'] == true,
      quietHoursStart:
          integer('quiet_hours_start', 22).clamp(0, 23).toInt(),
      quietHoursEnd: integer('quiet_hours_end', 7).clamp(0, 23).toInt(),
      pausedUntil: DateTime.tryParse(
        json['paused_until']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

class NeuraIntelligenceRecord {
  const NeuraIntelligenceRecord({
    required this.title,
    required this.body,
    required this.receipt,
  });

  final String title;
  final String body;
  final NeuraDecisionReceipt receipt;

  NeuraIntelligenceRecord copyWith({NeuraDecisionReceipt? receipt}) {
    return NeuraIntelligenceRecord(
      title: title,
      body: body,
      receipt: receipt ?? this.receipt,
    );
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'receipt': receipt.toJson(),
      };

  factory NeuraIntelligenceRecord.fromJson(Map<String, Object?> json) {
    final rawReceipt = json['receipt'];
    return NeuraIntelligenceRecord(
      title: 'Decision receipt',
      body: 'Private suggestion text is not retained in intelligence history.',
      receipt: NeuraDecisionReceipt.fromJson(
        rawReceipt is Map
            ? Map<String, Object?>.from(rawReceipt)
            : const <String, Object?>{},
      ),
    );
  }
}
