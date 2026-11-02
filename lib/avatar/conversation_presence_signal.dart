import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';

/// Translates a conversation surface's turn state into avatar presence events.
///
/// The chat screen knows when the microphone is open and when a reply has been
/// requested but has not produced any text yet. The avatar orchestrator only
/// hears about those moments through [NeuraEventBus]. This class is the seam
/// between the two: callers report their current state as often as they like
/// and only real transitions are emitted, so it is safe to call after every
/// `setState`.
///
/// Speaking is deliberately not handled here. The TTS viseme bridge already
/// emits talking, mouth and viseme events from the actual audio lifecycle.
///
/// Presentation only: no text, transcript, memory or identifier crosses this
/// seam, just two booleans.
class ConversationPresenceSignal {
  ConversationPresenceSignal({void Function(Object event)? emit})
      : _emit = emit ?? NeuraEventBus.I.emit;

  final void Function(Object event) _emit;

  bool _listening = false;
  bool _thinking = false;

  bool get listening => _listening;
  bool get thinking => _thinking;

  /// Reports the surface's current state.
  ///
  /// [listening] wins over [awaitingReply]: while the microphone is open the
  /// avatar is listening, never thinking. [suppressed] (Safe Mode, disposal)
  /// forces both off.
  void update({
    required bool listening,
    required bool awaitingReply,
    bool suppressed = false,
  }) {
    final nextListening = !suppressed && listening;
    final nextThinking = !suppressed && !nextListening && awaitingReply;

    // Clear before set so a listener never observes both states at once.
    if (_listening && !nextListening) {
      _listening = false;
      _emit(const NeuraListeningEvent(false));
    }
    if (_thinking && !nextThinking) {
      _thinking = false;
      _emit(const NeuraThinkingEvent(false));
    }
    if (!_listening && nextListening) {
      _listening = true;
      _emit(const NeuraListeningEvent(true));
    }
    if (!_thinking && nextThinking) {
      _thinking = true;
      _emit(const NeuraThinkingEvent(true));
    }
  }

  /// Returns the avatar to rest for anything this signal turned on.
  void reset() => update(listening: false, awaitingReply: false);
}
