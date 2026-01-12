import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// One job: play a looping ambient track (optionally switching when rooms change).
class NeuraAmbientAudioService {
  NeuraAmbientAudioService();

  final AudioPlayer _player = AudioPlayer();
  String? _currentAsset;
  bool _enabled = false;
  double _volume = 0.35;

  bool get enabled => _enabled;
  double get volume => _volume;

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) {
      await stop();
    } else if (_currentAsset != null) {
      await playLoop(_currentAsset!);
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
  }

  Future<void> playLoop(String assetPath) async {
    _currentAsset = assetPath;
    if (!_enabled) return;

    // Restart cleanly.
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(_volume);
    await _player.play(AssetSource(assetPath.replaceFirst('assets/', '')));
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
