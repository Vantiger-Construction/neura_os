import 'package:window_manager_plus/window_manager_plus.dart';

/// Marker passed as an extra arg to the floating avatar window so `main()`
/// can tell it apart from the primary app window.
const String kMascotWindowArgument = 'neura_mascot';

/// Owns the floating avatar window's lifecycle from the main engine's side:
/// creates it once (lazily), then shows/hides it as
/// [NeuraShellState.showAvatar] changes.
class MascotWindowService {
  MascotWindowService._();
  static final MascotWindowService I = MascotWindowService._();

  Future<WindowManagerPlus?>? _creating;

  Future<WindowManagerPlus?> _ensureCreated() {
    return _creating ??= WindowManagerPlus.createWindow([kMascotWindowArgument]);
  }

  Future<void> init({required bool visible}) async {
    final controller = await _ensureCreated();
    if (visible) {
      await controller?.show();
    }
  }

  /// Completes once the initial window-creation attempt (kicked off by
  /// [NeuraShellState] at boot) has settled, success or failure. Other
  /// first-time native-subsystem work should wait on this before running --
  /// this is the same "two native engines/windows initializing back to
  /// back" hazard that already caused a real audioplayers
  /// MissingPluginException race here (see NeuraShellState._spawnMascotWhenReady),
  /// now also confirmed to crash flutter_tts_plugin.dll (0xC0000005) when the
  /// app's first proactive TTS call raced this window's own engine spin-up.
  /// Resolves immediately if mascot creation was never triggered.
  Future<void> get initialCreationSettled async {
    final creating = _creating;
    if (creating == null) return;
    try {
      await creating;
    } catch (_) {
      // A mascot-window failure shouldn't block whoever is waiting on this.
    }
  }

  Future<void> setVisible(bool visible) async {
    final controller = await _ensureCreated();
    if (visible) {
      await controller?.show();
    } else {
      await controller?.hide();
    }
  }
}
