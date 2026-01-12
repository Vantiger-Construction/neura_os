import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/neura_room.dart';
import 'services/neura_ambient_audio_service.dart';

class NeuraShellState extends ChangeNotifier {
  static const _kRoomId = 'neura_shell.room_id';
  static const _kShowAvatar = 'neura_shell.show_avatar';
  static const _kAmbientEnabled = 'neura_shell.ambient_enabled';
  static const _kAmbientVolume = 'neura_shell.ambient_volume';
  static const _kAutoRoomSync = 'neura_shell.auto_room_sync';


  NeuraRoom _room = NeuraRoom.penthouse;
  bool _showAvatar = true;
  bool _ambientEnabled = false;
  double _ambientVolume = 0.35;
  bool _autoRoomSync = true;

  final NeuraAmbientAudioService _audio = NeuraAmbientAudioService();
  bool _loaded = false;

  bool get isLoaded => _loaded;
  NeuraRoom get room => _room;
  bool get showAvatar => _showAvatar;
  bool get ambientEnabled => _ambientEnabled;
  double get ambientVolume => _ambientVolume;
  bool get autoRoomSync => _autoRoomSync;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _room = NeuraRoom.fromId(prefs.getString(_kRoomId));
    _showAvatar = prefs.getBool(_kShowAvatar) ?? true;
    _ambientEnabled = prefs.getBool(_kAmbientEnabled) ?? false;
    _ambientVolume = (prefs.getDouble(_kAmbientVolume) ?? 0.35).clamp(0.0, 1.0);
    _autoRoomSync = prefs.getBool(_kAutoRoomSync) ?? true;

    await _audio.setVolume(_ambientVolume);
    await _audio.setEnabled(_ambientEnabled);
    final asset = _room.ambientSoundAsset;
    if (_ambientEnabled && asset != null) {
      await _audio.playLoop(asset);
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setRoom(NeuraRoom room) async {
    _room = room;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRoomId, room.id);

    final asset = room.ambientSoundAsset;
    if (_ambientEnabled && asset != null) {
      await _audio.playLoop(asset);
    }
  }

  Future<void> setShowAvatar(bool value) async {
    _showAvatar = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowAvatar, value);
  }

  Future<void> setAmbientEnabled(bool enabled) async {
    _ambientEnabled = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAmbientEnabled, enabled);

    await _audio.setEnabled(enabled);
    final asset = _room.ambientSoundAsset;
    if (enabled && asset != null) {
      await _audio.playLoop(asset);
    }
  }

  Future<void> setAmbientVolume(double volume) async {
    _ambientVolume = volume.clamp(0.0, 1.0);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kAmbientVolume, _ambientVolume);

    await _audio.setVolume(_ambientVolume);
  }

  Future<void> setAutoRoomSync(bool value) async {
    _autoRoomSync = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoRoomSync, value);
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }
}
