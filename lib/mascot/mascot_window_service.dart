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

  Future<void> setVisible(bool visible) async {
    final controller = await _ensureCreated();
    if (visible) {
      await controller?.show();
    } else {
      await controller?.hide();
    }
  }
}
