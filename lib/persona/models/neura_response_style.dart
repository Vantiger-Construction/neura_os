import 'package:flutter/foundation.dart';

@immutable
class NeuraResponseStyle {
  final String toneLabel; // e.g. "soft", "direct", "balanced"
  final double jokeFrequency; // 0.0 - 1.0
  final double depthLevel; // 0.0 - 1.0
  final double energyLevel; // 0.0 - 1.0
  final bool useDirectLanguage; // true = blunt / no sugarcoat
  final String difficulty; // "gentle" | "normal" | "challenge"
  final String systemPromptSnippet;

  const NeuraResponseStyle({
    required this.toneLabel,
    required this.jokeFrequency,
    required this.depthLevel,
    required this.energyLevel,
    required this.useDirectLanguage,
    required this.difficulty,
    required this.systemPromptSnippet,
  });

  Map<String, dynamic> toMap() => {
        'toneLabel': toneLabel,
        'jokeFrequency': jokeFrequency,
        'depthLevel': depthLevel,
        'energyLevel': energyLevel,
        'useDirectLanguage': useDirectLanguage,
        'difficulty': difficulty,
        'systemPromptSnippet': systemPromptSnippet,
      };
}
