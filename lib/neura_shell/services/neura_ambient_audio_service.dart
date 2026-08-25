import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../services/neura_audio_focus.dart';
import '../../reliability/safe_boot.dart';

/// Plays one looping local ambient track and automatically ducks it while
/// Neura speaks. Playback remains disabled in Safe Mode.
class NeuraAmbientAudioService {
  NeuraAmbientAudioService({
    NeuraAudioFocus? audioFocus,
  }) : _audioFocus = audioFocus ?? NeuraAudioFocus.instance {
    _speechSubscription = _audioFocus.speechActivity.listen((_) {
      unawaited(_applyEffectiveVolume());
    });
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  static const double _speechDuckFactor = 0.22;

  final AudioPlayer _player = AudioPlayer();
  final NeuraAudioFocus _audioFocus;
  StreamSubscription<bool>? _speechSubscription;
  String? _currentAsset;
  bool _enabled = false;
  bool _disposed = false;
  double _volume = 0.35;

  bool get enabled => _enabled;
  double get volume => _volume;
  bool get playbackAllowed => !SafeBoot.instance.safeMode.value;

  double get effectiveVolume =>
      _audioFocus.speechActive ? _volume * _speechDuckFactor : _volume;

  Future<void> setEnabled(bool enabled) async {
    if (_disposed) return;
    _enabled = enabled;
    if (!enabled || !playbackAllowed) {
      await stop();
    } else if (_currentAsset != null) {
      await playLoop(_currentAsset!);
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _applyEffectiveVolume();
  }

  Future<void> _applyEffectiveVolume() async {
    if (_disposed || !_enabled || !playbackAllowed) return;
    try {
      await _player.setVolume(effectiveVolume);
    } catch (_) {
      // Ambient audio is non-critical and must never crash the shell.
    }
  }

  Future<void> playLoop(String assetPath) async {
    _currentAsset = assetPath;
    if (_disposed || !_enabled || !playbackAllowed) return;

    try {
      await _player.stop();
      if (!playbackAllowed) return;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(effectiveVolume);
      if (!playbackAllowed) return;
      await _player.play(AssetSource(assetPath.replaceFirst('assets/', '')));
    } catch (_) {
      // Missing or unsupported ambient assets fail silently.
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    await _speechSubscription?.cancel();
    _speechSubscription = null;
    await stop();
    await _player.dispose();
  }

  void _onSafeModeChanged() {
    if (!playbackAllowed) unawaited(stop());
  }
}
