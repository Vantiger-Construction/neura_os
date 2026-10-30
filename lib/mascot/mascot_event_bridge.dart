import '../avatar/motion/neura_gesture.dart';
import '../avatar/neura_avatar_runtime_bridge.dart';
import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import '../core/neura_events_extra.dart';
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
    // ── Body-motion kinds (receivers ignore kinds they don't know) ──────────
    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraListeningEvent>(
          (e) => _send('listening', {'on': e.isListening})),
    );
    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraErrorEvent>((_) => _send('error', {})),
    );
    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraGestureEvent>((e) {
        // Only allow-listed gestures cross the isolate boundary.
        if (!NeuraGesture.wireAllowed.contains(e.gesture)) return;
        _send('gesture', {
          'gesture': e.gesture.wireName,
          'intensity': e.intensity.clamp(0.0, 1.0),
        });
      }),
    );
    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraMouthOpenEvent>((e) {
        // Throttle: visemes can fire per word; ~15 Hz is plenty for a bob.
        final now = DateTime.now();
        if (e.open > 0 && now.difference(_lastMouth).inMilliseconds < 66) {
          return;
        }
        _lastMouth = now;
        _send('mouth', {'open': e.open.clamp(0.0, 1.0)});
      }),
    );
    final snapshot = NeuraAvatarRuntimeBridge.instance.snapshot;
    void sendBody() {
      final s = snapshot.value;
      if (s == null) return;
      _send('body', {
        'motion': s.motion.name,
        'stance': s.stance.name,
        'safe': s.safeMode,
      });
    }

    snapshot.addListener(sendBody);
    _unsubscribers.add(() => snapshot.removeListener(sendBody));
    sendBody();
  }

  DateTime _lastMouth = DateTime.fromMillisecondsSinceEpoch(0);

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
