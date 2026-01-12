import 'package:flutter/foundation.dart';

import 'avatar_types.dart';

/// Global controller for driving avatar reactions.
///
/// Hook this up to:
/// - speech-to-text (listening)
/// - TTS playback (talking)
/// - network/tool calls (thinking)
/// - error handler (error)
/// - mood engine (mood/energy)
class AvatarController extends ChangeNotifier {
  AvatarSignals _signals = const AvatarSignals();

  // Optional dynamic inputs for renderers that support extra controls.
  // (e.g., Rive number inputs like mouthOpen/viseme).
  final Map<String, double> _numberInputs = <String, double>{};

  AvatarSignals get signals => _signals;

  Map<String, double> get numberInputs => Map<String, double>.unmodifiable(_numberInputs);

  double? getNumberInput(String name) => _numberInputs[name];

  void setNumberInput(String name, double value) {
    _numberInputs[name] = value;
    notifyListeners();
  }

  void setSignals(AvatarSignals next) {
    _signals = next;
    notifyListeners();
  }

  void update(AvatarSignals Function(AvatarSignals cur) fn) {
    _signals = fn(_signals);
    notifyListeners();
  }

  // Convenience helpers
  void setListening(bool v) => update((s) => s.copyWith(isListening: v));
  void setTalking(bool v) => update((s) => s.copyWith(isTalking: v));
  void setThinking(bool v) => update((s) => s.copyWith(isThinking: v));
  void setError(bool v) => update((s) => s.copyWith(isError: v));
  void setMood(double v) => update((s) => s.copyWith(mood: v.clamp(-1.0, 1.0)));
  void setEnergy(double v) => update((s) => s.copyWith(energy: v.clamp(0.0, 1.0)));

  void pulseWave() {
    // one-shot; renderers should interpret this as a trigger
    update((s) => s.copyWith(wave: true));
    update((s) => s.copyWith(wave: false));
  }

  void pulseBlink() {
    update((s) => s.copyWith(blink: true));
    update((s) => s.copyWith(blink: false));
  }
}
