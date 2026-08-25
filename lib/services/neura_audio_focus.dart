import 'dart:async';

/// Coordinates Neura-owned audio without inspecting or recording user content.
///
/// Speech acquires focus while it is audible. Ambient players listen for focus
/// changes and duck locally, then restore their configured volume. The counter
/// makes overlapping speech requests safe and prevents an early restore.
class NeuraAudioFocus {
  NeuraAudioFocus._();

  static final NeuraAudioFocus instance = NeuraAudioFocus._();

  final StreamController<bool> _speechActivity =
      StreamController<bool>.broadcast(sync: true);
  int _speechHolders = 0;

  Stream<bool> get speechActivity => _speechActivity.stream;
  bool get speechActive => _speechHolders > 0;

  NeuraAudioFocusLease acquireSpeech() {
    _speechHolders += 1;
    if (_speechHolders == 1) _speechActivity.add(true);
    return NeuraAudioFocusLease._(this);
  }

  void _releaseSpeech() {
    if (_speechHolders == 0) return;
    _speechHolders -= 1;
    if (_speechHolders == 0) _speechActivity.add(false);
  }
}

class NeuraAudioFocusLease {
  NeuraAudioFocusLease._(this._owner);

  NeuraAudioFocus? _owner;

  void release() {
    final owner = _owner;
    if (owner == null) return;
    _owner = null;
    owner._releaseSpeech();
  }
}
