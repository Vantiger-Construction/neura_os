import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../modules/core/app_log.dart';
import '../profiles/local_profile_service.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_error_pipeline.dart';

class SleepListenerService with WidgetsBindingObserver {
  SleepListenerService() {
    _liveInstances.add(this);
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.addListener(_onSafetyChanged);
    NeuraErrorPipeline.instance.fatalError.addListener(_onSafetyChanged);
  }

  static final Set<SleepListenerService> _liveInstances =
      <SleepListenerService>{};
  static bool _suspendedForDataWipe = false;
  static const _shutdownTimeout = Duration(seconds: 3);

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  // Set before requesting native capture, cleared only by an acknowledged Stop.
  // A timeout never establishes that a native operation has finished.
  bool _shutdownUnverified = false;
  bool _disposed = false;
  String? _currentPath;
  final Set<String> _currentTakePaths = <String>{};
  Future<void>? _startInFlight;
  Future<String>? _stopInFlight;
  Future<String?>? _nativeStopInFlight;
  Future<void>? _disposeInFlight;
  int _dataGeneration = 0;

  bool get isRecording => _recording;

  bool get _captureAllowed =>
      !_disposed &&
      !_suspendedForDataWipe &&
      !LocalProfileService.instance.enabled &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value &&
      NeuraErrorPipeline.instance.fatalError.value == null &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> startRecording() {
    if (!_captureAllowed ||
        _recording ||
        _shutdownUnverified ||
        _stopInFlight != null ||
        _nativeStopInFlight != null) {
      return Future<void>.value();
    }
    final existing = _startInFlight;
    if (existing != null) return existing;

    late final Future<void> pending;
    pending = _startRecording().whenComplete(() {
      if (identical(_startInFlight, pending)) _startInFlight = null;
    });
    _startInFlight = pending;
    return pending;
  }

  Future<void> _startRecording() async {
    final generation = _dataGeneration;
    if (!_mayCapture(generation) || !await _recorder.hasPermission()) return;
    if (!_mayCapture(generation)) return;

    final dir = await getApplicationDocumentsDirectory();
    if (!_mayCapture(generation)) return;
    final path =
        '${dir.path}/sleep_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _currentPath = path;
    _currentTakePaths
      ..clear()
      ..add(path);
    _shutdownUnverified = true;

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );
      if (!_mayCapture(generation)) {
        await _stopNative();
        await deleteLastRecording();
        return;
      }
      _recording = true;
    } catch (_) {
      // A rejected Start can still have acquired a native resource. Keep the
      // file and shutdown ownership until cleanup is positively acknowledged.
      if (_shutdownUnverified) await _stopNative();
      rethrow;
    }
  }

  bool _mayCapture(int generation) =>
      _captureAllowed && generation == _dataGeneration;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _onSafetyChanged();
  }

  void _onSafetyChanged() {
    if (_captureAllowed) return;
    // Invalidate synchronously, including a permission prompt that later
    // completes after Safe Mode/recovery has been cleared or focus returns.
    unawaited(_stopForSafety());
  }

  Future<void> _stopForSafety() async {
    try {
      await stopRecording();
    } catch (error, stack) {
      try {
        await AppLog.instance
            .caught('sleep_recording_stop_failed', error, stack);
      } catch (_) {}
    }
  }

  Future<String> stopRecording() {
    _dataGeneration++;
    _recording = false;
    final existing = _stopInFlight;
    if (existing != null) return existing;
    late final Future<String> pending;
    pending = _stopOnce().whenComplete(() {
      if (identical(_stopInFlight, pending)) _stopInFlight = null;
    });
    _stopInFlight = pending;
    return pending;
  }

  Future<String> _stopOnce() async {
    Object? drainFailure;
    final starting = _startInFlight;
    if (starting != null) {
      try {
        await starting.timeout(_shutdownTimeout);
      } catch (error) {
        drainFailure = error;
      }
    }
    if (_shutdownUnverified) await _stopNative();
    if (drainFailure != null) {
      throw StateError('Sleep recorder start could not be drained.');
    }
    return _captureAllowed ? (_currentPath ?? '') : '';
  }

  Future<String?> _stopNative() {
    final existing = _nativeStopInFlight;
    if (existing != null) return existing.timeout(_shutdownTimeout);
    late final Future<String?> pending;
    pending = _recorder.stop().then((path) {
      if (path != null && path.isNotEmpty) {
        _currentPath = path;
        _currentTakePaths.add(path);
      }
      _shutdownUnverified = false;
      return path;
    }).whenComplete(() {
      if (identical(_nativeStopInFlight, pending)) _nativeStopInFlight = null;
    });
    _nativeStopInFlight = pending;
    return pending.timeout(_shutdownTimeout);
  }

  Future<void> deleteLastRecording() async {
    // Native encoders may return a different final path. Retain both the
    // requested path and final output until each deletion is acknowledged.
    for (final path in _currentTakePaths.toList()) {
      await _deletePaths([path]);
      _currentTakePaths.remove(path);
      if (_currentPath == path) _currentPath = null;
    }
  }

  /// Stop every live recorder, even if an earlier instance fails shutdown.
  static Future<void> stopAllForProfiles() async {
    var failed = false;
    for (final service in _liveInstances.toList()) {
      try {
        await service.stopRecording();
        service._currentPath = null;
        service._currentTakePaths.clear();
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      throw StateError('Sleep recorder shutdown could not be verified.');
    }
  }

  static Future<void> resetAllAfterDataWipe() async {
    _suspendedForDataWipe = true;
    final services = List<SleepListenerService>.from(_liveInstances);
    for (final service in services) {
      service._dataGeneration++;
    }
    var failed = false;
    for (final service in services) {
      try {
        await service._resetAfterDataWipe();
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      throw StateError('Sleep recorder shutdown could not be verified.');
    }
  }

  Future<void> _resetAfterDataWipe() async {
    Object? shutdownFailure;
    try {
      await stopRecording();
      await _disposeInFlight?.timeout(_shutdownTimeout);
    } catch (error) {
      shutdownFailure = error;
    }
    await deleteLastRecording();
    if (shutdownFailure != null) {
      throw StateError('Sleep recorder shutdown could not be verified.');
    }
  }

  static Future<void> _deletePaths(Iterable<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> dispose() {
    if (!_disposed) {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      SafeBoot.instance.safeMode.removeListener(_onSafetyChanged);
      SafeBoot.instance.restartRequired.removeListener(_onSafetyChanged);
      NeuraErrorPipeline.instance.fatalError.removeListener(_onSafetyChanged);
    }
    if (!_liveInstances.contains(this)) return Future<void>.value();
    final existing = _disposeInFlight;
    if (existing != null) return existing.timeout(_shutdownTimeout);
    late final Future<void> pending;
    pending = _disposeOnce().whenComplete(() {
      if (identical(_disposeInFlight, pending)) _disposeInFlight = null;
    });
    _disposeInFlight = pending;
    return pending.timeout(_shutdownTimeout);
  }

  Future<void> _disposeOnce() async {
    await stopRecording();
    await _recorder.dispose();
    // Retain registry ownership on failure/timeout so a wipe cannot skip it.
    _liveInstances.remove(this);
  }
}
