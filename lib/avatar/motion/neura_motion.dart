// lib/avatar/motion/neura_motion.dart
//
// The live, app-wide motion runtime for Neura's in-process avatar surfaces.
//
// One shared [NeuraMotionEngine] so every in-app avatar (room presence, global
// host, presence view) moves as the same body. Inputs come only from
// already-public, content-free sources:
//
//   NeuraEventBus      talking / listening / thinking / error / mood / mouth /
//                      wave pulse / NeuraGestureEvent
//   NeuraCompanionPresence   authoritative phase leases
//   NeuraAvatarRuntimeBridge stance (room) for posture bias
//   ShellPrefs               Still / Subtle / Expressive
//   SafeBoot                 Safe Mode → frozen, neutral, no gestures
//
// The floating mascot runs in its own isolate and owns its own engine; it is
// fed the same signals through MascotEventBridge.

import 'package:flutter/foundation.dart';

import '../../core/neura_event_bus.dart';
import '../../core/neura_events.dart';
import '../../core/neura_events_extra.dart';
import '../../neura_shell/models/neura_room_presence_profile.dart';
import '../../reliability/safe_boot.dart';
import '../../services/neura_companion_presence.dart';
import '../../src/shell/shell_prefs.dart';
import '../neura_avatar_runtime_bridge.dart';
import 'neura_gesture.dart';
import 'neura_motion_engine.dart';

class NeuraMotion {
  NeuraMotion._();

  static final NeuraMotion instance = NeuraMotion._();

  final NeuraMotionEngine engine = NeuraMotionEngine();
  final Stopwatch _clock = Stopwatch()..start();
  Duration _last = Duration.zero;

  bool _started = false;

  /// True while the runtime is started. Bodies only tick when live, so idle
  /// widget tests (and any surface built before boot) stay perfectly still.
  final ValueNotifier<bool> live = ValueNotifier<bool>(false);
  final List<void Function()> _unsubs = [];

  // Bus-reported activity (OR'd with presence leases).
  bool _talking = false;
  bool _listening = false;
  bool _thinking = false;
  bool _error = false;

  /// Advance the shared engine to "now". Idempotent within a frame: every
  /// avatar widget can call this from its own ticker and the body is only
  /// simulated once.
  NeuraPose sample() {
    final now = _clock.elapsed;
    final dt = (now - _last).inMicroseconds / 1e6;
    if (dt < 0.002) return engine.pose;
    _last = now;
    return engine.tick(dt);
  }

  void start() {
    if (_started) return;
    _started = true;
    final bus = NeuraEventBus.I;

    _unsubs
      ..add(bus.on<NeuraTalkingEvent>((e) {
        _talking = e.isTalking;
        _syncPhase();
      }))
      ..add(bus.on<NeuraListeningEvent>((e) {
        _listening = e.isListening;
        _syncPhase();
      }))
      ..add(bus.on<NeuraThinkingEvent>((e) {
        _thinking = e.isThinking;
        _syncPhase();
      }))
      ..add(bus.on<NeuraErrorEvent>((_) {
        _error = true;
        _syncPhase();
        Future<void>.delayed(const Duration(seconds: 2), () {
          _error = false;
          _syncPhase();
        });
      }))
      ..add(bus.on<NeuraMoodEvent>((e) => engine.setMood(e.mood, e.energy)))
      ..add(bus.on<NeuraMouthOpenEvent>((e) => engine.setMouthOpen(e.open)))
      ..add(bus.on<NeuraPulseEvent>((e) {
        if (e.wave) engine.gesture(NeuraGesture.wave);
      }))
      ..add(bus.on<NeuraGestureEvent>(
          (e) => engine.gesture(e.gesture, intensity: e.intensity)));

    SafeBoot.instance.safeMode.addListener(_syncSafety);
    NeuraCompanionPresence.instance.state.addListener(_syncPhase);
    ShellPrefsController.instance.prefs.addListener(_syncPrefs);
    NeuraAvatarRuntimeBridge.instance.snapshot.addListener(_syncStance);
    _unsubs.add(() {
      SafeBoot.instance.safeMode.removeListener(_syncSafety);
      NeuraCompanionPresence.instance.state.removeListener(_syncPhase);
      ShellPrefsController.instance.prefs.removeListener(_syncPrefs);
      NeuraAvatarRuntimeBridge.instance.snapshot.removeListener(_syncStance);
    });

    _syncSafety();
    _syncPrefs();
    _syncStance();
    _syncPhase();
    live.value = true;
  }

  void stop() {
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    _started = false;
    live.value = false;
  }

  void _syncSafety() => engine.setFrozen(SafeBoot.instance.safeMode.value);

  void _syncPrefs() => engine.setMotionLevel(
        bodyLevelFor(ShellPrefsController.instance.prefs.value.companionMotion),
      );

  void _syncStance() {
    final snap = NeuraAvatarRuntimeBridge.instance.snapshot.value;
    if (snap != null) engine.setStance(bodyStanceFor(snap.stance));
  }

  void _syncPhase() {
    final presence = NeuraCompanionPresence.instance.state.value.phase;
    if (presence == NeuraPresencePhase.safeMode) {
      engine.setFrozen(true);
      return;
    }
    engine.setFrozen(SafeBoot.instance.safeMode.value);
    engine.setPhase(resolvePhase(
      error: _error,
      listening: _listening || presence == NeuraPresencePhase.listening,
      speaking: _talking || presence == NeuraPresencePhase.speaking,
      thinking: _thinking || presence == NeuraPresencePhase.thinking,
    ));
  }

  /// Same priority order as NeuraCompanionPresence (error wins first).
  @visibleForTesting
  static NeuraBodyPhase resolvePhase({
    required bool error,
    required bool listening,
    required bool speaking,
    required bool thinking,
  }) {
    if (error) return NeuraBodyPhase.error;
    if (listening) return NeuraBodyPhase.listening;
    if (speaking) return NeuraBodyPhase.speaking;
    if (thinking) return NeuraBodyPhase.thinking;
    return NeuraBodyPhase.idle;
  }

  static NeuraBodyMotionLevel bodyLevelFor(NeuraCompanionMotion m) =>
      switch (m) {
        NeuraCompanionMotion.still => NeuraBodyMotionLevel.still,
        NeuraCompanionMotion.subtle => NeuraBodyMotionLevel.subtle,
        NeuraCompanionMotion.expressive => NeuraBodyMotionLevel.expressive,
      };

  static NeuraBodyStance bodyStanceFor(NeuraRoomStance s) => switch (s) {
        NeuraRoomStance.welcoming => NeuraBodyStance.welcoming,
        NeuraRoomStance.reflective => NeuraBodyStance.reflective,
        NeuraRoomStance.playful => NeuraBodyStance.playful,
        NeuraRoomStance.grounding => NeuraBodyStance.grounding,
        NeuraRoomStance.dreaming => NeuraBodyStance.dreaming,
        NeuraRoomStance.guardian => NeuraBodyStance.guardian,
      };
}
