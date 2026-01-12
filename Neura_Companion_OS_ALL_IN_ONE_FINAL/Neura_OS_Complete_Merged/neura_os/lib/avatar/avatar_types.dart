import 'package:flutter/foundation.dart';

/// Supported avatar rendering backends.
enum AvatarFormat {
  rive,
  lottie,
  sprite,
  image,
}

/// A small, stable set of signals we can drive across all avatar formats.
///
/// Design goals:
/// - If an animation file changes (inputs removed/renamed), nothing crashes.
/// - If a format can't express a signal (e.g., Lottie), the renderer can ignore it.
@immutable
class AvatarSignals {
  final bool isListening;
  final bool isTalking;
  final bool isThinking;
  final bool isError;

  /// -1..1 (sad..happy) recommended.
  final double mood;

  /// 0..1 recommended.
  final double energy;

  /// Optional one-shot actions.
  final bool wave;
  final bool blink;

  const AvatarSignals({
    this.isListening = false,
    this.isTalking = false,
    this.isThinking = false,
    this.isError = false,
    this.mood = 0.0,
    this.energy = 0.5,
    this.wave = false,
    this.blink = false,
  });

  AvatarSignals copyWith({
    bool? isListening,
    bool? isTalking,
    bool? isThinking,
    bool? isError,
    double? mood,
    double? energy,
    bool? wave,
    bool? blink,
  }) {
    return AvatarSignals(
      isListening: isListening ?? this.isListening,
      isTalking: isTalking ?? this.isTalking,
      isThinking: isThinking ?? this.isThinking,
      isError: isError ?? this.isError,
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      wave: wave ?? this.wave,
      blink: blink ?? this.blink,
    );
  }
}

/// Canonical input names for Rive state machines.
///
/// Your .riv can use different names; just map them in [AvatarRiveConfig.inputNames].
class AvatarRiveInputs {
  static const String isListening = 'isListening';
  static const String isTalking = 'isTalking';
  static const String isThinking = 'isThinking';
  static const String isError = 'isError';
  static const String mood = 'mood';
  static const String energy = 'energy';
  static const String wave = 'wave';
  static const String blink = 'blink';
}
