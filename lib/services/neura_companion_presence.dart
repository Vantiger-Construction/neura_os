import 'package:flutter/foundation.dart';

import '../reliability/safe_boot.dart';

/// Content-free companion activity exposed to local UI surfaces.
///
/// This state intentionally carries no transcript, journal, prompt, or reply
/// text. Safe Mode always wins and invalidates active presence leases.
enum NeuraPresencePhase { idle, thinking, speaking, listening, safeMode }

@immutable
class NeuraPresenceSnapshot {
  const NeuraPresenceSnapshot(this.phase);

  final NeuraPresencePhase phase;

  bool get microphoneActive => phase == NeuraPresencePhase.listening;
  bool get voiceActive => phase == NeuraPresencePhase.speaking;
  bool get isSafeMode => phase == NeuraPresencePhase.safeMode;

  String get label => switch (phase) {
        NeuraPresencePhase.idle => 'Ready locally',
        NeuraPresencePhase.thinking => 'Thinking locally',
        NeuraPresencePhase.speaking => 'Speaking on this device',
        NeuraPresencePhase.listening => 'Listening on this device',
        NeuraPresencePhase.safeMode => 'Safe Mode · audio is off',
      };
}

/// Coordinates Neura's visible local presence without retaining user content.
class NeuraCompanionPresence {
  NeuraCompanionPresence({ValueListenable<bool>? safeMode})
      : _safeMode = safeMode ?? SafeBoot.instance.safeMode,
        _state = ValueNotifier<NeuraPresenceSnapshot>(
          NeuraPresenceSnapshot(
            (safeMode ?? SafeBoot.instance.safeMode).value
                ? NeuraPresencePhase.safeMode
                : NeuraPresencePhase.idle,
          ),
        ) {
    _safeMode.addListener(_onSafeModeChanged);
  }

  static final NeuraCompanionPresence instance = NeuraCompanionPresence();

  final ValueListenable<bool> _safeMode;
  final ValueNotifier<NeuraPresenceSnapshot> _state;
  final Map<NeuraPresencePhase, int> _leases = {};
  int _generation = 0;

  ValueListenable<NeuraPresenceSnapshot> get state => _state;

  NeuraPresenceLease? acquireListening() =>
      _acquire(NeuraPresencePhase.listening);

  NeuraPresenceLease? acquireSpeaking() =>
      _acquire(NeuraPresencePhase.speaking);

  NeuraPresenceLease? acquireThinking() =>
      _acquire(NeuraPresencePhase.thinking);

  NeuraPresenceLease? _acquire(NeuraPresencePhase phase) {
    if (_safeMode.value) {
      _emit();
      return null;
    }

    final generation = _generation;
    _leases[phase] = (_leases[phase] ?? 0) + 1;
    _emit();
    return NeuraPresenceLease._(() => _release(phase, generation));
  }

  void _release(NeuraPresencePhase phase, int generation) {
    if (generation != _generation) return;

    final count = _leases[phase] ?? 0;
    if (count <= 1) {
      _leases.remove(phase);
    } else {
      _leases[phase] = count - 1;
    }
    _emit();
  }

  void _onSafeModeChanged() {
    if (_safeMode.value) {
      _generation++;
      _leases.clear();
    }
    _emit();
  }

  void _emit() {
    final phase = _resolvePhase();
    if (_state.value.phase != phase) {
      _state.value = NeuraPresenceSnapshot(phase);
    }
  }

  NeuraPresencePhase _resolvePhase() {
    if (_safeMode.value) return NeuraPresencePhase.safeMode;
    if ((_leases[NeuraPresencePhase.listening] ?? 0) > 0) {
      return NeuraPresencePhase.listening;
    }
    if ((_leases[NeuraPresencePhase.speaking] ?? 0) > 0) {
      return NeuraPresencePhase.speaking;
    }
    if ((_leases[NeuraPresencePhase.thinking] ?? 0) > 0) {
      return NeuraPresencePhase.thinking;
    }
    return NeuraPresencePhase.idle;
  }

  @visibleForTesting
  void dispose() {
    _safeMode.removeListener(_onSafeModeChanged);
    _state.dispose();
  }
}

class NeuraPresenceLease {
  NeuraPresenceLease._(this._onRelease);

  final VoidCallback _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}
