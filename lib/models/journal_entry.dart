import 'package:flutter/foundation.dart';

@immutable
class JournalEntry {
  final String id;

  /// When the journal event originally occurred.
  final DateTime timestamp;

  /// When this revision was last changed.
  ///
  /// Older local entries do not contain this field, so conflict resolution
  /// falls back to [timestamp] without making existing journals unreadable.
  final DateTime? updatedAt;
  final String content;
  final String moodTag;
  final bool isVoice;

  const JournalEntry({
    required this.id,
    required this.timestamp,
    required this.content,
    this.updatedAt,
    this.moodTag = '',
    this.isVoice = false,
  });

  DateTime get effectiveUpdatedAt => updatedAt ?? timestamp;

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'updated_at': effectiveUpdatedAt.toUtc().toIso8601String(),
        'content': content,
        'moodTag': moodTag,
        'isVoice': isVoice,
      };

  factory JournalEntry.fromMap(Map<String, dynamic> map) => JournalEntry(
        id: map['id'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        updatedAt: map['updated_at'] == null
            ? null
            : DateTime.parse(map['updated_at'] as String),
        content: map['content'] as String,
        moodTag: map['moodTag'] as String? ?? '',
        isVoice: map['isVoice'] as bool? ?? false,
      );
}
