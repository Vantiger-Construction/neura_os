import 'dart:async';

import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import 'avatar_controller.dart';

/// Listens to NeuraEventBus and drives AvatarController signals.
/// This is the "nervous system" glue: events in → expressions out.
class AvatarOrchestrator {
  static AvatarOrchestrator? _active;

  final AvatarController controller;
  final NeuraEventBus bus;

  StreamSubscription<NeuraEvent>? _sub;
  Timer? _errorResetTimer;

  /// How long the avatar stays in the error state after an error event.
  final Duration errorHold;

  AvatarOrchestrator({
    required this.controller,
    required this.bus,
    this.errorHold = const Duration(seconds: 2),
  });

  void start() {
    if (!identical(_active, this)) {
      _active?.dispose();
      _active = this;
    }
    _sub ??= bus.stream.listen(_onEvent);
  }

  void _onEvent(NeuraEvent e) {
    switch (e) {
      case NeuraThinkingEvent():
        controller.setThinking(e.isThinking);
        break;
      case NeuraListeningEvent():
        controller.setListening(e.isListening);
        break;
      case NeuraTalkingEvent():
        controller.setTalking(e.isTalking);
        break;
      case NeuraMoodEvent():
        controller.setMood(e.mood);
        controller.setEnergy(e.energy);
        break;
      case NeuraPulseEvent():
        if (e.wave) controller.pulseWave();
        if (e.blink) controller.pulseBlink();
        break;
      case NeuraRouteEvent():
        // Tiny flavor: blink on room change.
        controller.pulseBlink();
        break;
      case NeuraErrorEvent():
        // "Dimensional Sync" behavior:
        // flip to error briefly, then recover.
        controller.setError(true);
        controller.setThinking(false);
        controller.setTalking(false);
        controller.setListening(false);

        _errorResetTimer?.cancel();
        _errorResetTimer = Timer(errorHold, () {
          _errorResetTimer = null;
          controller.setError(false);
        });
        break;
    }
  }

  void dispose() {
    _errorResetTimer?.cancel();
    _errorResetTimer = null;
    _sub?.cancel();
    _sub = null;
    if (identical(_active, this)) {
      _active = null;
    }
  }
}
