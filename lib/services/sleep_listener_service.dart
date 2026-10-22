import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class SleepListenerService {
  SleepListenerService() {
    _liveInstances.add(this);
  }

  static final Set<SleepListenerService> _liveInstances =
      <SleepListenerService>{};
  static bool _suspendedForDataWipe = false;

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _shutdownUnverified = false;
  String? _currentPath;
  Future<void>? _startInFlight;
  int _dataGeneration = 0;

  bool get isRecording => _recording;

  Future<void> startRecording() {
    if (_suspendedForDataWipe || _recording) return Future<void>.value();
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
    if (!await _recorder.hasPermission()) return;
    if (!_mayCapture(generation)) return;

    final dir = await getApplicationDocumentsDirectory();
    if (!_mayCapture(generation)) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/sleep_$ts.m4a';
    _currentPath = path;
    var startCompleted = false;

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
      startCompleted = true;
      if (!_mayCapture(generation)) {
        final paths = <String>{path};
        Object? cleanupFailure;
        try {
          final stoppedPath = await _recorder.stop();
          if (stoppedPath != null && stoppedPath.isNotEmpty) {
            paths.add(stoppedPath);
          }
        } catch (error) {
          cleanupFailure = error;
        }
        try {
          await _deletePaths(paths);
        } catch (error) {
          cleanupFailure ??= error;
        }
        _currentPath = null;
        if (cleanupFailure != null) {
          throw StateError(
            'Late sleep recording cleanup could not be verified.',
          );
        }
        return;
      }
      _recording = true;
    } catch (_) {
      _currentPath = null;
      if (startCompleted && !_mayCapture(generation)) rethrow;
    }
  }

  bool _mayCapture(int generation) =>
      !_suspendedForDataWipe && generation == _dataGeneration;

  Future<String> stopRecording() async {
    if (!_recording) return '';
    _recording = false;
    try {
      final path = await _recorder.stop();
      _currentPath = path;
    } catch (_) {}
    return _currentPath ?? '';
  }

  Future<void> deleteLastRecording() async {
    final path = _currentPath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      _currentPath = null;
    }
  }

  /// Stops and deletes recordings owned by every live sleep-listener screen
  /// before the documents-directory sweep runs.
  static Future<void> resetAllAfterDataWipe() async {
    _suspendedForDataWipe = true;
    final services = List<SleepListenerService>.from(_liveInstances);
    for (final service in services) {
      service._dataGeneration += 1;
    }
    var shutdownFailed = false;
    for (final service in services) {
      try {
        await service._resetAfterDataWipe();
      } catch (_) {
        shutdownFailed = true;
      }
    }
    if (shutdownFailed) {
      throw StateError('Sleep recorder shutdown could not be verified.');
    }
  }

  Future<void> _resetAfterDataWipe() async {
    Object? drainFailure;
    final pendingStart = _startInFlight;
    if (pendingStart != null) {
      try {
        await pendingStart.timeout(const Duration(seconds: 3));
      } catch (error) {
        drainFailure = error;
      }
    }
    final paths = <String>{
      if (_currentPath != null && _currentPath!.isNotEmpty) _currentPath!,
    };
    if (_recording || drainFailure != null || _shutdownUnverified) {
      _recording = false;
      _shutdownUnverified = true;
      try {
        final stoppedPath =
            await _recorder.stop().timeout(const Duration(seconds: 3));
        _shutdownUnverified = false;
        if (stoppedPath != null && stoppedPath.isNotEmpty) {
          paths.add(stoppedPath);
        }
      } catch (error) {
        drainFailure ??= error;
      }
    }
    _currentPath = null;
    await _deletePaths(paths);
    if (drainFailure != null) {
      throw StateError('Sleep recorder shutdown could not be verified.');
    }
  }

  static Future<void> _deletePaths(Iterable<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  void dispose() {
    _liveInstances.remove(this);
    _recorder.dispose();
  }
}
