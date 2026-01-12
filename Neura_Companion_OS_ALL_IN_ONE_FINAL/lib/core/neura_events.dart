import 'package:flutter/foundation.dart';

@immutable
abstract class NeuraEvent {
  const NeuraEvent();
}

/// App lifecycle / activity
class NeuraThinkingEvent extends NeuraEvent {
  final bool isThinking;
  const NeuraThinkingEvent(this.isThinking);
}

class NeuraListeningEvent extends NeuraEvent {
  final bool isListening;
  const NeuraListeningEvent(this.isListening);
}

class NeuraTalkingEvent extends NeuraEvent {
  final bool isTalking;
  const NeuraTalkingEvent(this.isTalking);
}

class NeuraErrorEvent extends NeuraEvent {
  final Object error;
  final StackTrace? stack;
  final String? hint;
  const NeuraErrorEvent(this.error, {this.stack, this.hint});
}

/// Mood/energy ranges are intentionally “soft”:
/// - mood: -1..1
/// - energy: 0..1
class NeuraMoodEvent extends NeuraEvent {
  final double mood;
  final double energy;
  const NeuraMoodEvent({required this.mood, required this.energy});
}

/// Navigation / rooms
class NeuraRouteEvent extends NeuraEvent {
  final String routeName;
  const NeuraRouteEvent(this.routeName);
}

/// One-shot pulses
class NeuraPulseEvent extends NeuraEvent {
  final bool wave;
  final bool blink;
  const NeuraPulseEvent._({required this.wave, required this.blink});

  const NeuraPulseEvent.wave() : this._(wave: true, blink: false);
  const NeuraPulseEvent.blink() : this._(wave: false, blink: true);
}
