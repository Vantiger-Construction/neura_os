import 'package:flutter/widgets.dart';
import '../neura_runtime/neura_bus.dart';
import 'models/neura_room.dart';
import 'services/neura_ambient_audio_service.dart';
import '../startup/neura_prefs_cache.dart';

/// Concrete [InheritedNotifier] subclass so [NeuraShell.of] can look it up
/// with `dependOnInheritedWidgetOfExactType`, which matches by exact runtime
/// type (the abstract `InheritedNotifier<NeuraShellState>` itself would never
/// match here).
class NeuraShellScope extends InheritedNotifier<NeuraShellState> {
  const NeuraShellScope({super.key, required super.notifier, required super.child});
}

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
    await NeuraPrefsCache.init();
    final prefs = NeuraPrefsCache.prefs;
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

    // Tell the runtime which room we're starting in.
    _emitRoomEnter(_room);
  }

  Future<void> setRoom(NeuraRoom room) async {
    _room = room;
    notifyListeners();

    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_kRoomId, room.id);

    final asset = room.ambientSoundAsset;
    if (_ambientEnabled && asset != null) {
      await _audio.playLoop(asset);
    }

    _emitRoomEnter(room);
  }

  /// Maps a [NeuraRoom] to the corresponding [NeuraRoomKey] and emits a
  /// [roomEnter] event so [NeuraRuntimeController] can react.
  void _emitRoomEnter(NeuraRoom room) {
    final key = _toRoomKey(room);
    NeuraBus.I.currentRoom = key;
    NeuraBus.I.emit(NeuraEvent(NeuraEventType.roomEnter, room: key));
  }

  static NeuraRoomKey _toRoomKey(NeuraRoom room) {
    switch (room.id) {
      case 'reflection_bay':
        return NeuraRoomKey.reflectionBay;
      case 'joy_lounge':
        return NeuraRoomKey.joyLounge;
      case 'mood_den':
        return NeuraRoomKey.moodDen;
      case 'dream_atrium':
        return NeuraRoomKey.dreamAtrium;
      case 'legacy_vault':
        return NeuraRoomKey.legacyVault;
      case 'settings':
        return NeuraRoomKey.settings;
      default:
        return NeuraRoomKey.penthouse;
    }
  }

  Future<void> setShowAvatar(bool value) async {
    _showAvatar = value;
    notifyListeners();
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setBool(_kShowAvatar, value);
  }

  Future<void> setAmbientEnabled(bool enabled) async {
    _ambientEnabled = enabled;
    notifyListeners();

    final prefs = NeuraPrefsCache.prefs;
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

    final prefs = NeuraPrefsCache.prefs;
    await prefs.setDouble(_kAmbientVolume, _ambientVolume);

    await _audio.setVolume(_ambientVolume);
  }

  Future<void> setAutoRoomSync(bool value) async {
    _autoRoomSync = value;
    notifyListeners();
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setBool(_kAutoRoomSync, value);
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }
}
