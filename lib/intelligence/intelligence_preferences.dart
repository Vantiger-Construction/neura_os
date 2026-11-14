import 'models.dart';
import 'room_attention_policy.dart';

enum NeuraProactivityLevel { off, subtle, balanced }

extension NeuraProactivityLevelPolicy on NeuraProactivityLevel {
  String get label => switch (this) {
        NeuraProactivityLevel.off => 'Off',
        NeuraProactivityLevel.subtle => 'Subtle',
        NeuraProactivityLevel.balanced => 'Balanced',
      };

  String get description => switch (this) {
        NeuraProactivityLevel.off =>
          'Never surface unsolicited companion suggestions.',
        NeuraProactivityLevel.subtle =>
          'At most one quiet, dismissible suggestion per day.',
        NeuraProactivityLevel.balanced =>
          'Context-sensitive suggestions with the existing attention limits.',
      };

  int get maxDailyCap => switch (this) {
        NeuraProactivityLevel.off => 0,
        NeuraProactivityLevel.subtle => 1,
        NeuraProactivityLevel.balanced => 3,
      };

  Duration get appOpenCooldown => switch (this) {
        NeuraProactivityLevel.off => const Duration(days: 365),
        NeuraProactivityLevel.subtle => const Duration(hours: 24),
        NeuraProactivityLevel.balanced => const Duration(hours: 12),
      };
}

class NeuraIntelligencePreferences {
  const NeuraIntelligencePreferences({
    this.enabled = true,
    this.proactivityLevel = NeuraProactivityLevel.balanced,
    this.allowSensitiveSignals = false,
    this.showDecisionReasons = true,
    this.maxDailySuggestions = 3,
    this.quietHoursEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 7,
    this.pausedUntil,
    this.roomAttention = const {},
  });

  /// Upper bounds for stored per-room choices. Room ids are short code
  /// constants; anything beyond these bounds is ignored when loading.
  static const int maxRoomAttentionChoices = 32;
  static const int maxRoomIdLength = 64;

  final bool enabled;
  final NeuraProactivityLevel proactivityLevel;
  final bool allowSensitiveSignals;
  final bool showDecisionReasons;
  final int maxDailySuggestions;
  final bool quietHoursEnabled;
  final int quietHoursStart;
  final int quietHoursEnd;
  final DateTime? pausedUntil;

  /// The user's per-room attention choices, keyed by `NeuraRoom.id`. Only
  /// choices stricter than the built-in table are kept; see
  /// [withRoomAttention]. The kernel merges these through
  /// [NeuraRoomAttentionPolicy.effectiveFor], so they can only tighten.
  final Map<String, NeuraRoomAttention> roomAttention;

  /// Sets the user's attention for [roomId]. Choosing a level that is not
  /// stricter than the room's built-in attention removes the user choice, so
  /// a built-in calm or private room can never be loosened.
  NeuraIntelligencePreferences withRoomAttention(
    String roomId,
    NeuraRoomAttention attention,
  ) {
    final id = roomId.trim();
    if (id.isEmpty || id.length > maxRoomIdLength) return this;
    final next = Map<String, NeuraRoomAttention>.of(roomAttention);
    if (attention.index <= NeuraRoomAttentionPolicy.forRoom(id).index) {
      next.remove(id);
    } else {
      if (!next.containsKey(id) && next.length >= maxRoomAttentionChoices) {
        return this;
      }
      next[id] = attention;
    }
    return copyWith(roomAttention: next);
  }

  bool get allowsProactiveSuggestions =>
      enabled && proactivityLevel != NeuraProactivityLevel.off;

  int get effectiveMaxDailySuggestions {
    if (!allowsProactiveSuggestions) return 0;
    final cap = proactivityLevel.maxDailyCap;
    final personalCap = maxDailySuggestions.clamp(1, 6).toInt();
    return personalCap < cap ? personalCap : cap;
  }

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
    NeuraProactivityLevel? proactivityLevel,
    bool? allowSensitiveSignals,
    bool? showDecisionReasons,
    int? maxDailySuggestions,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
    DateTime? pausedUntil,
    bool clearPause = false,
    Map<String, NeuraRoomAttention>? roomAttention,
  }) {
    final nextLevel = proactivityLevel ??
        (enabled == false
            ? NeuraProactivityLevel.off
            : enabled == true &&
                    this.proactivityLevel == NeuraProactivityLevel.off
                ? NeuraProactivityLevel.balanced
                : this.proactivityLevel);
    final requestedEnabled =
        enabled ?? (proactivityLevel == null ? this.enabled : true);
    final nextEnabled =
        requestedEnabled && nextLevel != NeuraProactivityLevel.off;
    return NeuraIntelligencePreferences(
      enabled: nextEnabled,
      proactivityLevel: nextLevel,
      allowSensitiveSignals:
          allowSensitiveSignals ?? this.allowSensitiveSignals,
      showDecisionReasons: showDecisionReasons ?? this.showDecisionReasons,
      maxDailySuggestions:
          (maxDailySuggestions ?? this.maxDailySuggestions).clamp(1, 6).toInt(),
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart:
          (quietHoursStart ?? this.quietHoursStart).clamp(0, 23).toInt(),
      quietHoursEnd: (quietHoursEnd ?? this.quietHoursEnd).clamp(0, 23).toInt(),
      pausedUntil: clearPause ? null : pausedUntil ?? this.pausedUntil,
      roomAttention: roomAttention == null
          ? this.roomAttention
          : Map<String, NeuraRoomAttention>.unmodifiable(roomAttention),
    );
  }

  Map<String, Object?> toJson() => {
        'v': 2,
        'enabled': allowsProactiveSuggestions,
        'proactivity_level': proactivityLevel.name,
        'allow_sensitive_signals': allowSensitiveSignals,
        'show_decision_reasons': showDecisionReasons,
        'max_daily_suggestions': maxDailySuggestions,
        'quiet_hours_enabled': quietHoursEnabled,
        'quiet_hours_start': quietHoursStart,
        'quiet_hours_end': quietHoursEnd,
        'paused_until': pausedUntil?.toUtc().toIso8601String(),
        'room_attention': {
          for (final entry in roomAttention.entries)
            if (entry.value != NeuraRoomAttention.open)
              entry.key: entry.value.name,
        },
      };

  factory NeuraIntelligencePreferences.fromJson(Map<String, Object?> json) {
    int integer(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    final legacyEnabled = json['enabled'] != false;
    final levelName = json['proactivity_level']?.toString();
    NeuraProactivityLevel? level;
    for (final candidate in NeuraProactivityLevel.values) {
      if (candidate.name == levelName) {
        level = candidate;
        break;
      }
    }
    final resolvedLevel = legacyEnabled
        ? level ?? NeuraProactivityLevel.balanced
        : NeuraProactivityLevel.off;
    return NeuraIntelligencePreferences(
      enabled: resolvedLevel != NeuraProactivityLevel.off,
      proactivityLevel: resolvedLevel,
      allowSensitiveSignals: json['allow_sensitive_signals'] == true,
      showDecisionReasons: json['show_decision_reasons'] != false,
      maxDailySuggestions: integer(
        'max_daily_suggestions',
        3,
      ).clamp(1, 6).toInt(),
      quietHoursEnabled: json['quiet_hours_enabled'] == true,
      quietHoursStart: integer('quiet_hours_start', 22).clamp(0, 23).toInt(),
      quietHoursEnd: integer('quiet_hours_end', 7).clamp(0, 23).toInt(),
      pausedUntil: DateTime.tryParse(
        json['paused_until']?.toString() ?? '',
      )?.toLocal(),
      roomAttention: _roomAttentionFromJson(json['room_attention']),
    );
  }

  /// Loads only well-formed, bounded choices that are stricter than the
  /// built-in table. Malformed entries are dropped, never widened.
  static Map<String, NeuraRoomAttention> _roomAttentionFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final choices = <String, NeuraRoomAttention>{};
    for (final entry in raw.entries) {
      if (choices.length >= maxRoomAttentionChoices) break;
      final key = entry.key;
      if (key is! String) continue;
      final id = key.trim();
      if (id.isEmpty || id.length > maxRoomIdLength) continue;
      final attention = switch (entry.value) {
        'calm' => NeuraRoomAttention.calm,
        'private' => NeuraRoomAttention.private,
        _ => null,
      };
      if (attention == null) continue;
      if (attention.index <= NeuraRoomAttentionPolicy.forRoom(id).index) {
        continue;
      }
      choices[id] = attention;
    }
    return Map<String, NeuraRoomAttention>.unmodifiable(choices);
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

  Map<String, Object?> toJson() => {'v': 1, 'receipt': receipt.toJson()};

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
