import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/sleep_listener_service.dart';
import 'package:record/record.dart';

import '../helpers/controlled_recorder.dart';
import '../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'timed-out disposal remains owned by wipe until native disposal completes',
      () async {
    final fixture = await DataWipeFixture.create();
    final original = RecordPlatform.instance;
    final platform = ControlledRecorder();
    RecordPlatform.instance = platform;
    await fixture.run(() async {
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final service = SleepListenerService();
      try {
        await service.startRecording();
        platform.disposeGate = Completer<void>();
        await expectLater(service.dispose(), throwsA(isA<TimeoutException>()));
        await expectLater(
            SleepListenerService.resetAllAfterDataWipe(), throwsStateError);
        expect(platform.disposals, 1);
        platform.disposeGate!.complete();
        await drainRecorderEvents();
        await SleepListenerService.resetAllAfterDataWipe();
        expect(platform.live, isEmpty);
        expect(platform.disposals, 1);
        fixture.expectIsolation();
      } finally {
        final gate = platform.disposeGate;
        if (gate != null && !gate.isCompleted) {
          gate.complete();
        }
        await service.dispose();
        RecordPlatform.instance = original;
      }
    });
  });
}
