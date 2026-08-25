import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import 'mascot_window_service.dart';

/// Forwards a small subset of [NeuraEventBus] events from the main engine to
/// the floating mascot window's separate engine, so the mascot can react
/// visually (glow/pulse) instead of sitting static regardless of what Neura
/// is doing. Each payload is versioned and primitives-only (method-channel
/// constraint) and decoded defensively on the receiving end -- see
/// mascot_window_app.dart's `onEventFromWindow`.
class MascotEventBridge {
  MascotEventBridge._();
  static final MascotEventBridge instance = MascotEventBridge._();

  static const String _method = 'neura_state';
  static const int _version = 1;

  bool _started = false;
  final List<void Function()> _unsubscribers = [];

  /// Call once, after [MascotWindowService.I.initialCreationSettled] --
  /// subscribing earlier is harmless (events just get swallowed as
  /// best-effort sends to a not-yet-created window) but there's no reason to
  /// pay the subscription cost before the mascot window can possibly exist.
  void start() {
    if (_started) return;
    _started = true;

    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraThinkingEvent>(
          (e) => _send('thinking', {'on': e.isThinking})),
    );
    _unsubscribers.add(
      NeuraEventBus.I
          .on<NeuraTalkingEvent>((e) => _send('talking', {'on': e.isTalking})),
    );
    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraMoodEvent>(
        (e) => _send('mood', {'mood': e.mood, 'energy': e.energy}),
      ),
    );
    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraPulseEvent>(
        (e) => _send('pulse', {'wave': e.wave, 'blink': e.blink}),
      ),
    );
  }

  void _send(String kind, Map<String, dynamic> data) {
    MascotWindowService.I.sendEvent(_method, {
      'v': _version,
      'kind': kind,
      ...data,
    });
  }

  void stop() {
    for (final unsub in _unsubscribers) {
      unsub();
    }
    _unsubscribers.clear();
    _started = false;
  }
}
