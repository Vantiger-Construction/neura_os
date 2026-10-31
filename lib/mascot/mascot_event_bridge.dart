import '../avatar/motion/neura_gesture.dart';

import 'package:flutter/widgets.dart';

import '../avatar/neura_avatar_runtime_bridge.dart';
import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import '../core/neura_events_extra.dart';
import 'mascot_window_service.dart';
import '../reliability/safe_boot.dart';

/// Forwards a small subset of [NeuraEventBus] events from the main engine to
/// the floating mascot window's separate engine, so the mascot can react
/// visually (glow/pulse) instead of sitting static regardless of what Neura
/// is doing. Each payload is versioned and primitives-only (method-channel
/// constraint) and decoded defensively on the receiving end -- see
/// mascot_window_app.dart's `onEventFromWindow`.
class MascotEventBridge with WidgetsBindingObserver {
  MascotEventBridge._();
  static final MascotEventBridge instance = MascotEventBridge._();

  static const String _method = 'neura_state';
  static const int _version = 1;

  bool _started = false;
  bool _foreground = true;
  final List<void Function()> _unsubscribers = [];

  /// Call once, after [MascotWindowService.I.initialCreationSettled] --
  /// subscribing earlier is harmless (events just get swallowed as
  /// best-effort sends to a not-yet-created window) but there's no reason to
  /// pay the subscription cost before the mascot window can possibly exist.
  void start() {
    if (_started) return;
    _started = true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_sendBody);
    SafeBoot.instance.restartRequired.addListener(_sendBody);

    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraThinkingEvent>(
        (e) => _send('thinking', {'on': e.isThinking}),
      ),
    );
    _unsubscribers.add(
      NeuraEventBus.I.on<NeuraTalkingEvent>(
        (e) => _send('talking', {'on': e.isTalking}),
      ),
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
        (e) => _send('listening', {'on': e.isListening}),
      ),
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
    snapshot.addListener(_sendBody);
    _unsubscribers.add(() => snapshot.removeListener(_sendBody));
    _sendBody();
  }

  void _sendBody() {
    final s = NeuraAvatarRuntimeBridge.instance.snapshot.value;
    _send('body', {
      'motion': s?.motion.name ?? 'still',
      'stance': s?.stance.name ?? 'welcoming',
      'safe': (s?.safeMode ?? true) ||
          SafeBoot.instance.safeMode.value ||
          SafeBoot.instance.restartRequired.value,
      'active': _started && _foreground,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sendBody();
  }

  DateTime _lastMouth = DateTime.fromMillisecondsSinceEpoch(0);

  void _send(String kind, Map<String, dynamic> data) {
    if (!_foreground && kind != 'body') return;
    MascotWindowService.I.sendEvent(_method, {
      'v': _version,
      'kind': kind,
      ...data,
    });
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_sendBody);
    SafeBoot.instance.restartRequired.removeListener(_sendBody);
    _foreground = false;
    _sendBody();
    for (final unsub in _unsubscribers) {
      unsub();
    }
    _unsubscribers.clear();
    _started = false;
  }
}
