import '../behavior/behavior_engine.dart';

/// Controls Neura's presence state (speaking, idle, thinking, listening, etc.).
///
/// States are mutually exclusive — only one is active at a time.
/// Call [applyDecision] after each [BehaviorEngine.decideNext] to keep
/// presence in sync with the current behavioural intent.
class NeuraPresenceController {
  String _state = BehaviorAction.idle;

  /// The current presence state (mirrors [BehaviorAction] constants).
  String get state => _state;

  bool get isIdle => _state == BehaviorAction.idle;
  bool get isSpeaking => _state == BehaviorAction.speak;
  bool get isListening => _state == BehaviorAction.listen;
  bool get isThinking => _state == BehaviorAction.think;
  bool get isComforting => _state == BehaviorAction.comfort;
  bool get isCelebrating => _state == BehaviorAction.celebrate;

  /// Directly set the speaking flag (used by TTS / voice pipeline).
  void setSpeaking(bool value) {
    _state = value ? BehaviorAction.speak : BehaviorAction.idle;
  }

  /// Applies a [BehaviorDecision] from the engine, updating presence state.
  void applyDecision(BehaviorDecision decision) {
    switch (decision.action) {
      case BehaviorAction.speak:
      case BehaviorAction.listen:
      case BehaviorAction.think:
      case BehaviorAction.comfort:
      case BehaviorAction.celebrate:
      case BehaviorAction.idle:
        _state = decision.action;
      default:
        _state = BehaviorAction.idle;
    }
  }
}
