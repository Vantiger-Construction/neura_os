import 'package:flutter/foundation.dart';

import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import 'neura_chat_policy.dart';

/// Shared runtime channel for model-requested presentation tone.
///
/// The current tone is exposed as a notifier for UI/motor consumers and is
/// also translated onto Neura's existing mood/energy event channel. The
/// floating mascot already consumes that channel, so model tone changes have
/// an immediate visual effect without adding a second mascot protocol.
class NeuraToneRuntime {
  NeuraToneRuntime._();
  static final NeuraToneRuntime instance = NeuraToneRuntime._();

  final ValueNotifier<String> tone = ValueNotifier<String>('warm_companion');

  bool setTone(String value) {
    if (!NeuraChatPolicy.knownTones.contains(value)) return false;
    if (tone.value != value) tone.value = value;

    final visual = _visualFor(value);
    NeuraEventBus.I.emit(
      NeuraMoodEvent(mood: visual.mood, energy: visual.energy),
    );
    return true;
  }

  void resetAfterDataWipe() {
    // Do not emit a runtime event here: the startup audit subscriber would
    // recreate the just-deleted timeline during the wipe itself.
    tone.value = 'warm_companion';
  }

  static _ToneVisual _visualFor(String value) {
    switch (value) {
      case 'strategist':
        return const _ToneVisual(mood: 0.15, energy: 0.72);
      case 'calm_wellness':
        return const _ToneVisual(mood: 0.35, energy: 0.28);
      case 'cinematic_guide':
        return const _ToneVisual(mood: 0.45, energy: 0.82);
      case 'quiet_private':
        return const _ToneVisual(mood: 0.05, energy: 0.16);
      case 'warm_companion':
      default:
        return const _ToneVisual(mood: 0.65, energy: 0.48);
    }
  }
}

class _ToneVisual {
  final double mood;
  final double energy;

  const _ToneVisual({required this.mood, required this.energy});
}
