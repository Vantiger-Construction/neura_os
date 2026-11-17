import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/sleep_listener_service.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';

import 'helpers/data_wipe_fixture.dart';

class _SyntheticRecorder extends Fake
    with MockPlatformInterfaceMixin
    implements RecordPlatform {
  final paths = <String, String>{};
  final live = <String>{};
  final stopCalls = <String>[];
  final failedStops = <String>{};
  final _states = <String, StreamController<RecordState>>{};
  final _stops = <String, StreamController<RecordStop>>{};
  int starts = 0;
  int disposals = 0;
  final disposed = Completer<void>();

  @override
  Future<void> create(String recorderId) async {
    _states[recorderId] = StreamController<RecordState>.broadcast();
    _stops[recorderId] = StreamController<RecordStop>.broadcast();
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      _states[recorderId]!.stream;

  @override
  Stream<RecordStop> onStopped(String recorderId) => _stops[recorderId]!.stream;

  @override
  Future<bool> isRecording(String recorderId) async =>
      live.contains(recorderId);

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) async {
    starts += 1;
    paths[recorderId] = path;
    live.add(recorderId);
    // Synthetic bytes, written only within the fixture's guarded documents.
    await File(path).writeAsString('synthetic recording');
    _states[recorderId]!.add(RecordState.record);
  }

  @override
  Future<String?> stop(String recorderId) async {
    stopCalls.add(recorderId);
    if (failedStops.contains(recorderId)) {
      throw StateError('synthetic recorder stop failure');
    }
    if (live.remove(recorderId)) {
      _states[recorderId]!.add(RecordState.stop);
      _stops[recorderId]!.add(
        RecordStop(reason: RecordStopReason.stop, path: paths[recorderId]),
      );
    }
    return paths[recorderId];
  }

  @override
  Future<void> dispose(String recorderId) async {
    if (live.contains(recorderId)) await stop(recorderId);
    await _states.remove(recorderId)!.close();
    await _stops.remove(recorderId)!.close();
    disposals += 1;
    if (disposals == 2) disposed.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'one failed recorder shutdown cannot skip another recorder or prevent retry',
      () async {
    final f = await DataWipeFixture.create();
    final original = RecordPlatform.instance;
    final recorder = _SyntheticRecorder();
    RecordPlatform.instance = recorder;
    await f.run(() async {
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final first = SleepListenerService();
      final second = SleepListenerService();
      addTearDown(() async {
        await first.dispose();
        await second.dispose();
        try {
          await recorder.disposed.future.timeout(const Duration(seconds: 5));
        } finally {
          RecordPlatform.instance = original;
        }
      });
      await first.startRecording();
      await second.startRecording();
      expect(recorder.starts, 2);
      expect(first.isRecording, isTrue);
      expect(second.isRecording, isTrue);
      final firstId = recorder.paths.keys.first;
      final secondId = recorder.paths.keys.last;
      recorder.failedStops.add(firstId);
      // A failure during an ordinary Stop must remain owned by wipe/retry.
      await expectLater(first.stopRecording(), throwsStateError);
      await first.startRecording();
      expect(recorder.starts, 2);
      await expectLater(
        NeuraDataWipeService.wipeAllLocalData(),
        throwsA(isA<NeuraDataWipeException>().having((e) => e.failedSteps,
            'failed steps', contains('sleep recording shutdown'))),
      );
      expect(SafeBoot.instance.safeMode.value, isTrue);
      expect(recorder.stopCalls, containsAll([firstId, secondId]));
      expect(second.isRecording, isFalse);
      expect(recorder.live, {firstId});
      for (final path in recorder.paths.values) {
        expect(await File(path).exists(), isFalse);
      }
      final attempts = recorder.stopCalls.where((id) => id == firstId).length;
      recorder.failedStops.clear();
      await NeuraDataWipeService.wipeAllLocalData();
      expect(recorder.live, isEmpty);
      expect(recorder.stopCalls.where((id) => id == firstId),
          hasLength(attempts + 1));
      await NeuraDataWipeService.wipeAllLocalData();
      await first.startRecording();
      await second.startRecording();
      expect(recorder.starts, 2);
      for (final path in recorder.paths.values) {
        expect(await File(path).exists(), isFalse);
      }
      f.expectIsolation();
    });
  });
}
