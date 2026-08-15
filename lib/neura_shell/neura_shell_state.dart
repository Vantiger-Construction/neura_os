import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../mascot/mascot_event_bridge.dart';
import '../mascot/mascot_window_service.dart';
import '../neura_runtime/neura_bus.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';
import '../startup/neura_startup_coordinator.dart';
import 'models/neura_room.dart';
import 'services/neura_ambient_audio_service.dart';

@visibleForTesting
bool supportsNeuraMascot({
  required TargetPlatform platform,
  required bool isWeb,
}) =>
    !isWeb && platform == TargetPlatform.windows;

/// Concrete [InheritedNotifier] subclass so [NeuraShell.of] can look it up
/// with `dependOnInheritedWidgetOfExactType`, which matches by exact runtime
/// type (the abstract `InheritedNotifier<NeuraShellState>` itself would never
/// match here).
class NeuraShellScope extends InheritedNotifier<NeuraShellState> {
  const NeuraShellScope({
    super.key,
    required super.notifier,
    required super.child,
  });
}

class NeuraShellState extends ChangeNotifier {
  static const _kRoomId = 'neura_shell.room_id';
  static const _kShowAvatar = 'neura_shell.show_avatar';
  static const _kAmbientEnabled = 'neura_shell.ambient_enabled';
  static const _kAmbientVolume = 'neura_shell.ambient_volume';
  static const _kAutoRoomSync = 'neura_shell.auto_room_sync';

  NeuraShellState() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
    NeuraStartupCoordinator.instance.ready.addListener(_onStartupReady);
  }

  NeuraRoom _room = NeuraRoom.penthouse;
  bool _showAvatar = true;
  bool _ambientEnabled = false;
  double _ambientVolume = 0.35;
  bool _autoRoomSync = true;

  // Construct the plugin-backed player only after startup has resolved Safe
  // Mode. Merely creating a platform audio object can register native state,
  // which Safe Mode is intended to avoid entirely.
  NeuraAmbientAudioService? _audio;
  bool _loaded = false;
  bool _disposed = false;
  bool _optionalShellServicesActive = false;
  bool _mascotStarted = false;
  bool _mascotBridgeStarted = false;
  Future<void>? _loadInFlight;
  Future<void>? _optionalActivationInFlight;

  bool get isLoaded => _loaded;
  NeuraRoom get room => _room;
  bool get showAvatar => _showAvatar;
  bool get ambientEnabled => _ambientEnabled;
  double get ambientVolume => _ambientVolume;
  bool get autoRoomSync => _autoRoomSync;

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    final existing = _loadInFlight;
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = _load().whenComplete(() {
      if (identical(_loadInFlight, operation)) _loadInFlight = null;
    });
    _loadInFlight = operation;
    return operation;
  }

  Future<void> _load() async {
    await NeuraPrefsCache.init();
    if (_disposed) return;
    final prefs = NeuraPrefsCache.prefs;
    _room = NeuraRoom.fromId(prefs.getString(_kRoomId));
    _showAvatar = prefs.getBool(_kShowAvatar) ?? true;
    _ambientEnabled = prefs.getBool(_kAmbientEnabled) ?? false;
    _ambientVolume =
        (prefs.getDouble(_kAmbientVolume) ?? 0.35).clamp(0.0, 1.0);
    _autoRoomSync = prefs.getBool(_kAutoRoomSync) ?? true;

    _loaded = true;
    notifyListeners();

    // Tell the runtime which room we're starting in.
    _emitRoomEnter(_room);

    // Audio and the floating mascot are optional native services. Wait until
    // startup has resolved Safe Mode before touching either plugin.
    unawaited(_activateOptionalShellServicesWhenReady());
  }

  void _onStartupReady() {
    if (_disposed || _loaded) return;
    if (!NeuraStartupCoordinator.instance.ready.value) return;
    unawaited(load().catchError((_) {}));
  }

  Future<void> _activateOptionalShellServicesWhenReady() {
    final existing = _optionalActivationInFlight;
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = _activateOptionalShellServices().whenComplete(() {
      if (identical(_optionalActivationInFlight, operation)) {
        _optionalActivationInFlight = null;
      }
    });
    _optionalActivationInFlight = operation;
    return operation;
  }

  Future<void> _activateOptionalShellServices() async {
    final ready = NeuraStartupCoordinator.instance.ready;
    if (!ready.value) {
      final completer = Completer<void>();
      void listener() {
        if (ready.value) {
          ready.removeListener(listener);
          completer.complete();
        }
      }

      ready.addListener(listener);
      await completer.future;
    }
    if (_disposed || SafeBoot.instance.safeMode.value) return;

    try {
      final audio = _audio ??= NeuraAmbientAudioService();
      await audio.setVolume(_ambientVolume);
      if (_disposed || SafeBoot.instance.safeMode.value) return;
      await audio.setEnabled(_ambientEnabled);
      if (_disposed || SafeBoot.instance.safeMode.value) {
        await audio.setEnabled(false);
        return;
      }
      final asset = _room.ambientSoundAsset;
      if (_ambientEnabled && asset != null) {
        await audio.playLoop(asset);
      }
      _optionalShellServicesActive = true;
    } catch (_) {
      _optionalShellServicesActive = false;
    }

    if (_disposed || SafeBoot.instance.safeMode.value) {
      await _suspendOptionalShellServices();
      return;
    }
    if (!supportsNeuraMascot(
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
    )) {
      return;
    }

    try {
      await MascotWindowService.I.init(visible: _showAvatar);
      _mascotStarted = true;
      if (_disposed || SafeBoot.instance.safeMode.value) {
        await MascotWindowService.I.setVisible(false);
        return;
      }
      MascotEventBridge.instance.start();
      _mascotBridgeStarted = true;
    } catch (_) {
      // The companion window is optional; the main app remains usable.
    }
  }

  void _onSafeModeChanged() {
    if (_disposed || !_loaded) return;
    if (SafeBoot.instance.safeMode.value) {
      unawaited(_suspendOptionalShellServices());
    } else if (NeuraStartupCoordinator.instance.ready.value) {
      unawaited(_activateOptionalShellServicesWhenReady());
    }
  }

  Future<void> _suspendOptionalShellServices() async {
    final audio = _audio;
    if (_optionalShellServicesActive && audio != null) {
      try {
        await audio.setEnabled(false);
      } catch (_) {}
      _optionalShellServicesActive = false;
    }
    if (_mascotBridgeStarted) {
      MascotEventBridge.instance.stop();
      _mascotBridgeStarted = false;
    }
    if (_mascotStarted) {
      try {
        await MascotWindowService.I.setVisible(false);
      } catch (_) {}
    }
  }

  Future<void> setRoom(NeuraRoom room) async {
    _room = room;
    notifyListeners();

    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_kRoomId, room.id);

    final asset = room.ambientSoundAsset;
    if (_ambientEnabled &&
        _optionalShellServicesActive &&
        !SafeBoot.instance.safeMode.value &&
        asset != null) {
      await _audio?.playLoop(asset);
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
    if (_mascotStarted) {
      await MascotWindowService.I.setVisible(
        value && !SafeBoot.instance.safeMode.value,
      );
    } else if (value &&
        !SafeBoot.instance.safeMode.value &&
        NeuraStartupCoordinator.instance.ready.value) {
      await _activateOptionalShellServicesWhenReady();
    }
  }

  Future<void> setAmbientEnabled(bool enabled) async {
    _ambientEnabled = enabled;
    notifyListeners();

    final prefs = NeuraPrefsCache.prefs;
    await prefs.setBool(_kAmbientEnabled, enabled);

    if (SafeBoot.instance.safeMode.value ||
        !NeuraStartupCoordinator.instance.ready.value) {
      if (_optionalShellServicesActive) await _audio?.setEnabled(false);
      _optionalShellServicesActive = false;
      return;
    }

    final audio = _audio ??= NeuraAmbientAudioService();
    await audio.setEnabled(enabled);
    if (_disposed || SafeBoot.instance.safeMode.value) {
      await audio.setEnabled(false);
      _optionalShellServicesActive = false;
      return;
    }
    _optionalShellServicesActive = true;
    final asset = _room.ambientSoundAsset;
    if (enabled && asset != null) {
      await audio.playLoop(asset);
    }
  }

  Future<void> setAmbientVolume(double volume) async {
    _ambientVolume = volume.clamp(0.0, 1.0);
    notifyListeners();

    final prefs = NeuraPrefsCache.prefs;
    await prefs.setDouble(_kAmbientVolume, _ambientVolume);

    if (!SafeBoot.instance.safeMode.value &&
        _optionalShellServicesActive) {
      await _audio?.setVolume(_ambientVolume);
    }
  }

  Future<void> setAutoRoomSync(bool value) async {
    _autoRoomSync = value;
    notifyListeners();
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setBool(_kAutoRoomSync, value);
  }

  @override
  void dispose() {
    _disposed = true;
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    NeuraStartupCoordinator.instance.ready.removeListener(_onStartupReady);
    if (_mascotBridgeStarted) MascotEventBridge.instance.stop();
    final audio = _audio;
    if (audio != null) unawaited(audio.dispose());
    super.dispose();
  }
}
