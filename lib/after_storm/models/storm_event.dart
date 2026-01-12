import 'package:flutter/foundation.dart';

@immutable
class StormEvent {
  final String id;
  final DateTime timestamp;
  final String intensity; // mild / medium / severe
  final String primaryFeeling; // angry / scared / sad / numb / etc.
  final String shortSummary; // 1-2 sentence "what happened"
  final String needNow; // what do you need most right now
  final bool safetyRisk; // if user hinted at self-harm / danger
  final Map<String, dynamic> meta; // extra tags

  const StormEvent({
    required this.id,
    required this.timestamp,
    required this.intensity,
    required this.primaryFeeling,
    required this.shortSummary,
    required this.needNow,
    required this.safetyRisk,
    this.meta = const {},
  });

  StormEvent copyWith({
    String? id,
    DateTime? timestamp,
    String? intensity,
    String? primaryFeeling,
    String? shortSummary,
    String? needNow,
    bool? safetyRisk,
    Map<String, dynamic>? meta,
  }) {
    return StormEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      intensity: intensity ?? this.intensity,
      primaryFeeling: primaryFeeling ?? this.primaryFeeling,
      shortSummary: shortSummary ?? this.shortSummary,
      needNow: needNow ?? this.needNow,
      safetyRisk: safetyRisk ?? this.safetyRisk,
      meta: meta ?? this.meta,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'intensity': intensity,
        'primaryFeeling': primaryFeeling,
        'shortSummary': shortSummary,
        'needNow': needNow,
        'safetyRisk': safetyRisk,
        'meta': meta,
      };

  factory StormEvent.fromMap(Map<String, dynamic> map) {
    return StormEvent(
      id: map['id'] as String,
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now(),
      intensity: map['intensity'] as String? ?? 'unknown',
      primaryFeeling: map['primaryFeeling'] as String? ?? 'unknown',
      shortSummary: map['shortSummary'] as String? ?? '',
      needNow: map['needNow'] as String? ?? '',
      safetyRisk: map['safetyRisk'] as bool? ?? false,
      meta: (map['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}
