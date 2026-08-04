import 'package:flutter/foundation.dart';

/// A guided self-reflection prompt from an evidence-based therapeutic
/// framework (CBT/DBT/ACT). These are journaling prompts, not diagnosis or
/// treatment - Neura does not claim to provide therapy.
@immutable
class TherapyPrompt {
  final String id;
  final String title;
  final String instruction;
  final String method; // 'CBT', 'DBT', or 'ACT'

  const TherapyPrompt({
    required this.id,
    required this.title,
    required this.instruction,
    required this.method,
  });
}

/// A saved user response to a [TherapyPrompt].
@immutable
class TherapyResponse {
  final String id;
  final String promptId;
  final String method;
  final String promptTitle;
  final String text;
  final DateTime timestamp;

  const TherapyResponse({
    required this.id,
    required this.promptId,
    required this.method,
    required this.promptTitle,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'promptId': promptId,
        'method': method,
        'promptTitle': promptTitle,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TherapyResponse.fromMap(Map<String, dynamic> map) => TherapyResponse(
        id: map['id'] as String,
        promptId: map['promptId'] as String,
        method: map['method'] as String,
        promptTitle: map['promptTitle'] as String,
        text: map['text'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
}
