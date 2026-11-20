import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/sleep_listener_service.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';
import 'package:record/record.dart';

import '../helpers/controlled_recorder.dart';
import '../helpers/data_wipe_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledRecorder platform;
  late RecordPlatform original;
  late SleepListenerService service;
  late DataWipeFixture fixture;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    original = RecordPlatform.instance;
    platform = ControlledRecorder();
    RecordPlatform.instance = platform;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraErrorPipeline.instance.fatalError.value = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    service = SleepListenerService();
  });

  tearDown(() async {
    platform.failedStops.clear();
    platform.failedDisposals.clear();
    await fixture.run(() async {
      await service.dispose();
      fixture.expectIsolation();
    });
    RecordPlatform.instance = original;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraErrorPipeline.instance.fatalError.value = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final reason in ['Safe Mode', 'restart', 'recovery', 'background']) {
    void invalidate() {
      switch (reason) {
        case 'Safe Mode':
          SafeBoot.instance.safeMode.value = true;
          SafeBoot.instance.safeMode.value = false;
        case 'restart':
          SafeBoot.instance.restartRequired.value = true;
          SafeBoot.instance.restartRequired.value = false;
        case 'recovery':
          NeuraErrorPipeline.instance.fatalError.value = const NeuraFatalError(
            source: 'synthetic',
            phase: 'test',
          );
          NeuraErrorPipeline.instance.fatalError.value = null;
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    }

    test('permission completion after $reason cannot start or restart capture',
        () async {
      await fixture.run(() async {
        platform.permissionGate = Completer<bool>();
        final starting = service.startRecording();
        await drainRecorderEvents();
        expect(platform.permissions, 1);
        invalidate();
        platform.permissionGate!.complete(true);
        await starting;
        await drainRecorderEvents();
        expect(platform.starts, 0);
        expect(service.isRecording, isFalse);
      });
    });

    test('active capture stops on $reason and stays stopped after recovery',
        () async {
      await fixture.run(() async {
        await service.startRecording();
        expect(service.isRecording, isTrue);
        invalidate();
        await drainRecorderEvents();
        expect(platform.live, isEmpty);
        expect(service.isRecording, isFalse);
        expect(platform.starts, 1);
      });
    });
  }

  test('Safe Mode, restart and background reject before requesting permission',
      () async {
    await fixture.run(() async {
      SafeBoot.instance.safeMode.value = true;
      await service.startRecording();
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = true;
      await service.startRecording();
      SafeBoot.instance.restartRequired.value = false;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await service.startRecording();
      expect(platform.permissions, 0);
      expect(platform.starts, 0);
    });
  });

  test(
      'denied permission and Windows-style capture denial never claim recording',
      () async {
    await fixture.run(() async {
      platform.granted = false;
      await service.startRecording();
      expect(platform.starts, 0);
      platform.granted = true;
      platform.rejectStart = true;
      await expectLater(service.startRecording(), throwsStateError);
      expect(platform.live, isEmpty);
      expect(service.isRecording, isFalse);
    });
  });

  test(
      'normal Stop failure is visible, blocks restart, and permits an explicit Stop retry',
      () async {
    await fixture.run(() async {
      await service.startRecording();
      final id = platform.live.single;
      platform.failedStops.add(id);
      await expectLater(service.stopRecording(), throwsStateError);
      await service.startRecording();
      expect(platform.starts, 1);
      expect(platform.live, {id});
      platform.failedStops.clear();
      await service.stopRecording();
      expect(platform.live, isEmpty);
      expect(platform.stopCalls, [id, id]);
    });
  });

  test(
      'Stop before the first sample drains the late start without resurrection',
      () async {
    await fixture.run(() async {
      platform.startGate = Completer<void>();
      final starting = service.startRecording();
      await untilRecorderStarts(platform, 1);
      expect(platform.starts, 1);
      final stopping = service.stopRecording();
      platform.startGate!.complete();
      await starting;
      await stopping;
      expect(platform.live, isEmpty);
      expect(service.isRecording, isFalse);
    });
  });

  test(
      'Stop timeout remains uncertain and repeated Stop joins the native operation',
      () async {
    await fixture.run(() async {
      await service.startRecording();
      platform.stopGate = Completer<void>();
      await expectLater(
          service.stopRecording(), throwsA(isA<TimeoutException>()));
      await service.startRecording();
      expect(platform.starts, 1);
      final stopping = service.stopRecording();
      platform.stopGate!.complete();
      await stopping;
      expect(platform.stopCalls, hasLength(1));
      expect(platform.live, isEmpty);
    });
  });

  test('deleting a take removes requested and native final paths', () async {
    await fixture.run(() async {
      await service.startRecording();
      final id = platform.live.single;
      final requested = File(platform.paths[id]!);
      final returned =
          await fixture.seed('${fixture.documents.path}/final.m4a');
      platform.returnedPaths[id] = returned.path;
      expect(await service.stopRecording(), returned.path);
      await service.deleteLastRecording();
      expect(await requested.exists(), isFalse);
      expect(await returned.exists(), isFalse);
      await service.deleteLastRecording();
      fixture.expectIsolation();
    });
  });

  test('late-start cleanup removes both paths after Stop revokes capture',
      () async {
    await fixture.run(() async {
      final startGate = platform.startGate = Completer<void>();
      final startEntered = platform.startEntered = Completer<String>();
      final starting = service.startRecording();
      try {
        final id =
            await startEntered.future.timeout(const Duration(seconds: 3));
        expect(platform.live.single, id);
        final requested = File(platform.paths[id]!);
        final returned =
            await fixture.seed('${fixture.documents.path}/late.m4a');
        platform.returnedPaths[id] = returned.path;
        final stopping = service.stopRecording();
        startGate.complete();
        await starting;
        await stopping;
        expect(platform.live, isEmpty);
        expect(await requested.exists(), isFalse);
        expect(await returned.exists(), isFalse);
        fixture.expectIsolation();
      } finally {
        // Do not leave teardown blocked if an assertion fails before release.
        if (!startGate.isCompleted) startGate.complete();
      }
    });
  });

  test('disposal invalidates a pending permission and cannot capture afterward',
      () async {
    await fixture.run(() async {
      platform.permissionGate = Completer<bool>();
      final starting = service.startRecording();
      await drainRecorderEvents();
      final disposing = service.dispose();
      platform.permissionGate!.complete(true);
      await starting;
      await disposing;
      await service.startRecording();
      expect(platform.starts, 0);
    });
  });
}
