import 'dart:async';
import 'dart:io';

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
  int starts = 0;
  int disposals = 0;
  final disposed = Completer<void>();

  @override
  Future<void> create(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

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
  }

  @override
  Future<String?> stop(String recorderId) async {
    stopCalls.add(recorderId);
    if (failedStops.contains(recorderId))
      throw StateError('synthetic recorder stop failure');
    live.remove(recorderId);
    return paths[recorderId];
  }

  @override
  Future<void> dispose(String recorderId) async {
    live.remove(recorderId);
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
      final first = SleepListenerService();
      final second = SleepListenerService();
      addTearDown(() async {
        first.dispose();
        second.dispose();
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
      recorder.failedStops.clear();
      await NeuraDataWipeService.wipeAllLocalData();
      expect(recorder.live, isEmpty);
      expect(recorder.stopCalls.where((id) => id == firstId), hasLength(2));
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
