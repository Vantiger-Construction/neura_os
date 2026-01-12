import 'package:flutter/foundation.dart';

@immutable
class DreamEntry {
  final String id;
  final DateTime timestamp;
  final String transcript;
  // Additional AI interpretation fields
  final String interpretation;
  final String moodSummary;

  const DreamEntry({
    required this.id,
    required this.timestamp,
    required this.transcript,
    this.interpretation = '',
    this.moodSummary = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'transcript': transcript,
        'interpretation': interpretation,
        'moodSummary': moodSummary,
      };

  factory DreamEntry.fromMap(Map<String, dynamic> map) => DreamEntry(
        id: map['id'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        transcript: map['transcript'] as String,
        interpretation: map['interpretation'] as String? ?? '',
        moodSummary: map['moodSummary'] as String? ?? '',
      );
}
