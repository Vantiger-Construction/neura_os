// lib/avatar/avatar_rive_inputs.dart
//
// Canonical input names for Rive state machines.
// Missing inputs should be ignored by the runtime safely.

class AvatarRiveInputs {
  // Existing canonical inputs (keep stable).
  static const String isListening = 'isListening';
  static const String isTalking = 'isTalking';
  static const String isThinking = 'isThinking';
  static const String isError = 'isError';
  static const String mood = 'mood';
  static const String energy = 'energy';
  static const String wave = 'wave';
  static const String blink = 'blink';

  // Optional viseme inputs (safe if absent):
  static const String mouthOpen = 'mouthOpen'; // Number 0..1
  static const String viseme = 'viseme'; // Number 0..N
}
