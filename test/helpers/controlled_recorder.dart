import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';

/// Synthetic platform only: no permission UI, microphone, device or user audio.
class ControlledRecorder extends Fake
    with MockPlatformInterfaceMixin
    implements RecordPlatform {
  final states = <String, StreamController<RecordState>>{};
  final stops = <String, StreamController<RecordStop>>{};
  final audio = <String, StreamController<Uint8List>>{};
  final paths = <String, String>{};
  final live = <String>{};
  final stopCalls = <String>[];
  final failedStops = <String>{};
  final failedDisposals = <String>{};
  Completer<bool>? permissionGate;
  Completer<void>? startGate;
  Completer<void>? stopGate;
  Completer<void>? disposeGate;
  bool granted = true;
  bool rejectStart = false;
  int permissions = 0;
  int starts = 0;
  int disposals = 0;
  int polls = 0;

  @override
  Future<void> create(String recorderId) async {
    states[recorderId] = StreamController<RecordState>.broadcast();
    stops[recorderId] = StreamController<RecordStop>.broadcast();
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) => states[recorderId]!.stream;

  @override
  Stream<RecordStop> onStopped(String recorderId) => stops[recorderId]!.stream;

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async {
    permissions++;
    return permissionGate == null ? granted : await permissionGate!.future;
  }

  Future<void> _start(String recorderId) async {
    starts++;
    live.add(recorderId);
    await startGate?.future;
    if (rejectStart) throw StateError('Synthetic capture startup denial.');
    states[recorderId]!.add(RecordState.record);
  }

  @override
  Future<void> start(String recorderId, RecordConfig config, {required String path}) async {
    paths[recorderId] = path;
    await File(path).writeAsString('synthetic recording');
    await _start(recorderId);
  }

  @override
  Future<Stream<Uint8List>> startStream(String recorderId, RecordConfig config) async {
    audio[recorderId] = StreamController<Uint8List>.broadcast();
    await _start(recorderId);
    return audio[recorderId]!.stream;
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async {
    polls++;
    return Amplitude(current: -10, max: -10);
  }

  @override
  Future<bool> isRecording(String recorderId) async => live.contains(recorderId);

  @override
  Future<String?> stop(String recorderId) async {
    stopCalls.add(recorderId);
    if (failedStops.contains(recorderId)) throw StateError('Synthetic Stop failure.');
    await stopGate?.future;
    if (live.remove(recorderId)) {
      states[recorderId]!.add(RecordState.stop);
      stops[recorderId]!.add(RecordStop(reason: RecordStopReason.stop, path: paths[recorderId]));
    }
    return paths[recorderId];
  }

  @override
  Future<void> dispose(String recorderId) async {
    disposals++;
    if (failedDisposals.contains(recorderId)) throw StateError('Synthetic disposal failure.');
    await disposeGate?.future;
    live.remove(recorderId);
    await audio.remove(recorderId)?.close();
    await states.remove(recorderId)?.close();
    await stops.remove(recorderId)?.close();
  }
}

Future<void> drainRecorderEvents() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
