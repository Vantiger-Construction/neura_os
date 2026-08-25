import 'dart:async';

import 'package:window_manager_plus/window_manager_plus.dart';

import '../startup/neura_error_pipeline.dart';

/// Marker passed as an extra arg to the floating avatar window so `main()`
/// can tell it apart from the primary app window.
const String kMascotWindowArgument = 'neura_mascot';

/// Owns the floating avatar window's lifecycle from the main engine's side:
/// creates it once (lazily), then shows/hides it as
/// [NeuraShellState.showAvatar] changes.
class MascotWindowService {
  MascotWindowService._();
  static final MascotWindowService I = MascotWindowService._();

  // Allocated eagerly (not lazily inside _ensureCreated) so
  // initialCreationSettled can safely await it regardless of whether
  // _ensureCreated has actually been called yet -- see that getter's doc
  // comment for the real crash this fixes.
  final Completer<WindowManagerPlus?> _creationCompleter =
      Completer<WindowManagerPlus?>();
  bool _creationStarted = false;
  bool _disabledForProcess = false;
  Future<void> _creationBarrier = Future<void>.value();

  /// Holds secondary-window creation until primary window-manager bootstrap
  /// has settled. The main app can still render immediately; only the optional
  /// mascot waits on this barrier.
  void deferCreationUntil(Future<void> barrier) {
    if (_creationStarted || _disabledForProcess) return;
    _creationBarrier = barrier;
  }

  /// Permanently removes secondary-window creation from this isolate's
  /// lifetime. The Windows bootstrap uses this when its role channel or
  /// window-manager plugin is unavailable; retrying later could otherwise
  /// spawn another engine into the same broken bootstrap path recursively.
  /// A clean process restart is the only resume boundary.
  void disableForProcess() {
    _disabledForProcess = true;
    if (!_creationCompleter.isCompleted) {
      _creationCompleter.complete(null);
    }
  }

  bool get disabledForProcess => _disabledForProcess;

  Future<WindowManagerPlus?> _ensureCreated() {
    if (_disabledForProcess) return Future<WindowManagerPlus?>.value(null);
    if (!_creationStarted) {
      _creationStarted = true;
      unawaited(_createAfterBootstrap());
    }
    return _creationCompleter.future;
  }

  Future<void> _createAfterBootstrap() async {
    try {
      await _creationBarrier;
      if (_disabledForProcess) return;

      final controller =
          await WindowManagerPlus.createWindow([kMascotWindowArgument]);
      if (_disabledForProcess) {
        try {
          await controller?.hide();
        } catch (_) {}
        return;
      }
      if (!_creationCompleter.isCompleted) {
        _creationCompleter.complete(controller);
      }
    } catch (error, stackTrace) {
      NeuraErrorPipeline.instance.captureBootstrapWarning(
        error,
        stackTrace,
        source: 'mascot_window_create',
      );
      // A failed primary bootstrap or secondary-window creation must never be
      // retried recursively from another engine in the same process.
      disableForProcess();
    }
  }

  Future<void> init({required bool visible}) async {
    if (_disabledForProcess) return;
    final controller = await _ensureCreated();
    if (visible && !_disabledForProcess) {
      await controller?.show();
    }
  }

  /// Completes once the initial window-creation attempt (kicked off by
  /// [NeuraShellState] at boot) has settled, success or failure. Other
  /// first-time native-subsystem work should wait on this before running --
  /// this is the same "two native engines/windows initializing back to
  /// back" hazard that already caused a real audioplayers
  /// MissingPluginException race here (see NeuraShellState._spawnMascotWhenReady),
  /// and confirmed to crash flutter_tts_plugin.dll (0xC0000005) when the
  /// app's first proactive TTS call raced this window's own engine spin-up.
  ///
  /// Root cause of that crash recurring even after the first fix (which
  /// awaited this same getter): the old implementation checked a lazily-set
  /// field (`_creating`) and returned immediately if it was still null --
  /// but "null" didn't reliably mean "creation will never happen", it also
  /// meant "creation hasn't been *requested* yet by whichever async path
  /// owns that (NeuraShellState._spawnMascotWhenReady)". A caller reaching
  /// this getter in that narrow window would wrongly conclude there was
  /// nothing to wait for and proceed immediately, racing the mascot window
  /// creation that started moments later. Waiting on an eagerly-allocated
  /// Completer removes that race entirely: creation is always triggered
  /// exactly once by [NeuraShellState.load] on every real boot, so this
  /// simply waits for it -- capped at 8s so a genuinely-never-triggered
  /// caller (defensive; not expected in this app's real boot path) still
  /// can't hang forever.
  Future<void> get initialCreationSettled async {
    try {
      await _creationCompleter.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Timed out, or a mascot-window failure -- either way, whoever's
      // waiting on this shouldn't be blocked forever.
    }
  }

  Future<void> setVisible(bool visible) async {
    if (_disabledForProcess) return;
    final controller = await _ensureCreated();
    if (_disabledForProcess) return;
    if (visible) {
      await controller?.show();
    } else {
      await controller?.hide();
    }
  }

  /// Best-effort, fire-and-forget message to the mascot window's own engine
  /// (see [WindowListener.onEventFromWindow] in mascot_window_app.dart).
  /// Never throws -- this is purely a visual hint, so a delivery failure
  /// (window not created yet, window closed, IPC hiccup) should just mean
  /// "the mascot doesn't react this time", not a crash anywhere upstream.
  Future<void> sendEvent(String method, Map<String, dynamic> args) async {
    if (_disabledForProcess) return;
    try {
      final controller = await _ensureCreated();
      if (controller == null || _disabledForProcess) return;
      await WindowManagerPlus.current.invokeMethodToWindow(
        controller.id,
        method,
        args,
      );
    } catch (_) {
      // Swallow -- see doc comment above.
    }
  }
}
