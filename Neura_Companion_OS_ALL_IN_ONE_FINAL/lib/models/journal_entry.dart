import 'package:flutter/foundation.dart';

@immutable
class JournalEntry {
  final String id;
  final DateTime timestamp;
  final String content;
  final String moodTag;
  final bool isVoice;

  const JournalEntry({
    required this.id,
    required this.timestamp,
    required this.content,
    this.moodTag = '',
    this.isVoice = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'content': content,
        'moodTag': moodTag,
        'isVoice': isVoice,
      };

  factory JournalEntry.fromMap(Map<String, dynamic> map) => JournalEntry(
        id: map['id'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        content: map['content'] as String,
        moodTag: map['moodTag'] as String? ?? '',
        isVoice: map['isVoice'] as bool? ?? false,
      );
}
