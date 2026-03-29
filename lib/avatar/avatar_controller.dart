import 'package:flutter/foundation.dart';

import 'avatar_types.dart';

class AvatarController extends ChangeNotifier {
  AvatarSignals _signals = const AvatarSignals();
  final Map<String, double> _numberInputs = <String, double>{};

  AvatarSignals get signals => _signals;

  double numberInput(String key) => _numberInputs[key] ?? 0.0;

  void setNumberInput(String key, double value) {
    _numberInputs[key] = value;
    notifyListeners();
  }

  void setListening(bool value) {
    _signals = _signals.copyWith(isListening: value);
    notifyListeners();
  }

  void setTalking(bool value) {
    _signals = _signals.copyWith(isTalking: value);
    notifyListeners();
  }

  void setThinking(bool value) {
    _signals = _signals.copyWith(isThinking: value);
    notifyListeners();
  }

  void setError(bool value) {
    _signals = _signals.copyWith(isError: value);
    notifyListeners();
  }

  void setMood(double value) {
    _signals = _signals.copyWith(mood: value);
    notifyListeners();
  }

  void setEnergy(double value) {
    _signals = _signals.copyWith(energy: value);
    notifyListeners();
  }

  void pulseWave() {
    _signals = _signals.copyWith(wave: true);
    notifyListeners();
    _signals = _signals.copyWith(wave: false);
    notifyListeners();
  }

  void pulseBlink() {
    _signals = _signals.copyWith(blink: true);
    notifyListeners();
    _signals = _signals.copyWith(blink: false);
    notifyListeners();
  }
}
