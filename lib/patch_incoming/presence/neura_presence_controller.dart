import '../behavior/behavior_engine.dart';

/// Controls Neura's presence state (speaking, idle, thinking, etc.).
class NeuraPresenceController {
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  void setSpeaking(bool value) {
    _speaking = value;
  }

  void applyDecision(BehaviorDecision decision) {
    // Stub: map behavior decisions to presence states.
  }
}
