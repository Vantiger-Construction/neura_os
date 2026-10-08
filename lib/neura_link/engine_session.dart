import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../reliability/safe_boot.dart';
import '../startup/neura_error_pipeline.dart';

enum EngineSessionState {
  disabled,
  starting,
  idle,
  working,
  paused,
  error,
  unavailable,
  blocked,
}

/// Native code owns the credential and client. No credential, executable, URL,
/// free-form input or action argument crosses this interface.
class EngineSession extends ChangeNotifier with WidgetsBindingObserver {
  EngineSession({
    MethodChannel channel = const MethodChannel(
      'neura/engine_synthetic_session',
    ),
    ValueListenable<bool>? safeMode,
    ValueListenable<NeuraFatalError?>? recovery,
    bool? supported,
  })  : _channel = channel,
        _safeMode = safeMode ?? SafeBoot.instance.safeMode,
        _recovery = recovery ?? NeuraErrorPipeline.instance.fatalError,
        _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _safeMode.addListener(_onSafetyChanged);
    _recovery.addListener(_onSafetyChanged);
    _onSafetyChanged();
  }

  final MethodChannel _channel;
  final ValueListenable<bool> _safeMode;
  final ValueListenable<NeuraFatalError?> _recovery;
  final bool _supported;
  EngineSessionState _state = EngineSessionState.disabled;
  Timer? _pollTimer;
  int _generation = 0;
  bool _foreground = true;
  bool _blocked = false;
  bool _disposed = false;
  bool _pausing = false;

  EngineSessionState get state => _state;
  bool get canStart =>
      !_disposed &&
      !_blocked &&
      _foreground &&
      (_state == EngineSessionState.disabled ||
          _state == EngineSessionState.error ||
          _state == EngineSessionState.unavailable);
  bool get canPause =>
      !_disposed &&
      !_blocked &&
      _foreground &&
      (_state == EngineSessionState.starting ||
          _state == EngineSessionState.working ||
          _state == EngineSessionState.idle);
  bool get canResume =>
      !_disposed &&
      !_blocked &&
      _foreground &&
      !_pausing &&
      _state == EngineSessionState.paused;

  Future<void> start() async {
    if (!canStart) return;
    if (!_supported) {
      _update(EngineSessionState.unavailable);
      return;
    }
    final generation = ++_generation;
    _update(EngineSessionState.starting);
    await _requestState('startSynthetic', generation);
  }

  Future<void> pause() async {
    if (!canPause) return;
    final generation = ++_generation;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pausing = true;
    _update(EngineSessionState.paused);
    await _requestState('pauseSynthetic', generation);
    if (!_disposed && generation == _generation) {
      _pausing = false;
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (!canResume) return;
    final generation = ++_generation;
    _pollTimer?.cancel();
    _pollTimer = null;
    _update(EngineSessionState.starting);
    await _requestState('resumeSynthetic', generation);
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation && _foreground && !_blocked;

  Future<void> _requestState(String method, int generation) async {
    if (!_isCurrent(generation)) return;
    EngineSessionState next;
    try {
      final label = await _channel
          .invokeMethod<String>(method)
          .timeout(const Duration(seconds: 5));
      next = switch (label) {
        'disabled' => EngineSessionState.disabled,
        'starting' => EngineSessionState.starting,
        'idle' => EngineSessionState.idle,
        'working' => EngineSessionState.working,
        'paused' => EngineSessionState.paused,
        'blocked' => EngineSessionState.blocked,
        'unavailable' => EngineSessionState.unavailable,
        _ => EngineSessionState.error,
      };
    } catch (_) {
      // Never render, log, export or persist exception or native payload text.
      next = EngineSessionState.error;
    }
    if (!_isCurrent(generation)) return;
    _update(next);
    // Listeners can synchronously pause, stop, dispose or enter safety mode.
    // Recheck before scheduling a poll or stopping a replacement generation.
    if (!_isCurrent(generation)) return;
    if (next == EngineSessionState.error ||
        next == EngineSessionState.unavailable) {
      await stop();
      if (!_disposed && generation + 1 == _generation && !_blocked) {
        _update(next);
      }
      return;
    }
    if (next == EngineSessionState.starting ||
        next == EngineSessionState.working ||
        next == EngineSessionState.idle ||
        next == EngineSessionState.paused) {
      _pollTimer?.cancel();
      final delay = next == EngineSessionState.starting ||
              next == EngineSessionState.working
          ? const Duration(milliseconds: 100)
          : const Duration(seconds: 1);
      _pollTimer = Timer(delay, () {
        unawaited(_requestState('syntheticStatus', generation));
      });
    }
  }

  void _update(EngineSessionState next) {
    _state = next;
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() => _end('stopSynthetic');

  Future<void> _end(String method) async {
    ++_generation;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pausing = false;
    _update(
      _blocked ? EngineSessionState.blocked : EngineSessionState.disabled,
    );
    if (!_supported) return;
    try {
      await _channel.invokeMethod<String>(method);
    } catch (_) {
      // The Windows owner independently stops on hide, deactivate and destroy.
    }
  }

  void _onSafetyChanged() {
    if (_safeMode.value || _recovery.value != null) {
      _blocked = true;
      unawaited(_end('blockSynthetic'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safeMode.removeListener(_onSafetyChanged);
    _recovery.removeListener(_onSafetyChanged);
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
