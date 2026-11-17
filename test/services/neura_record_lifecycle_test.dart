import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/ambient_listening_prefs.dart';
import 'package:neuro_companion/services/ambient_listening_service.dart';
import 'package:neuro_companion/services/neura_voice_pack.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';
import 'package:record/record.dart';

import '../helpers/controlled_recorder.dart';
import '../helpers/data_wipe_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledRecorder platform;
  late RecordPlatform original;
  late DataWipeFixture fixture;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    original = RecordPlatform.instance;
    platform = ControlledRecorder();
    RecordPlatform.instance = platform;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraErrorPipeline.instance.fatalError.value = null;
    AmbientListeningPrefsController.instance.enabled.value = true;
  });

  tearDown(() {
    RecordPlatform.instance = original;
    AmbientListeningPrefsController.instance.enabled.value = false;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraErrorPipeline.instance.fatalError.value = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final consumer in ['ambient', 'voice pack']) {
    Future<void> run(Future<void> Function(Future<void> Function() start, Future<void> Function() stop) body) async {
      await fixture.run(() async {
        final ambient = consumer == 'ambient' ? AmbientListeningService.forTesting() : null;
        final voice = consumer == 'voice pack' ? NeuraVoicePack.forTesting() : null;
        try {
          await body(ambient?.start ?? voice!.startMic, ambient?.stop ?? voice!.stopMic);
        } finally {
          platform.failedStops.clear();
          if (ambient != null) await ambient.dispose();
          if (voice != null) await voice.dispose();
          fixture.expectIsolation();
        }
      });
    }

    for (final reason in ['Safe Mode', 'restart', 'recovery', 'background', 'Stop']) {
      test('$consumer: delayed permission stays revoked after $reason is cleared', () async {
        await run((start, stop) async {
          platform.permissionGate = Completer<bool>();
          final starting = start();
          await drainRecorderEvents();
          expect(platform.permissions, 1);
          Future<void>? stopping;
          switch (reason) {
            case 'Safe Mode':
              SafeBoot.instance.safeMode.value = true;
              SafeBoot.instance.safeMode.value = false;
            case 'restart':
              SafeBoot.instance.restartRequired.value = true;
              SafeBoot.instance.restartRequired.value = false;
            case 'recovery':
              NeuraErrorPipeline.instance.fatalError.value = const NeuraFatalError(source: 'synthetic', phase: 'test');
              NeuraErrorPipeline.instance.fatalError.value = null;
            case 'background':
              binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
              binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            case 'Stop':
              stopping = stop();
          }
          platform.permissionGate!.complete(true);
          await starting;
          await stopping;
          await drainRecorderEvents();
          expect(platform.starts, 0);
        });
      });
    }

    for (final terminal in ['stream close', 'stream error', 'platform stop', 'route pause']) {
      test('$consumer: $terminal releases capture and requires a fresh request', () async {
        await run((start, stop) async {
          await start();
          final id = platform.live.single;
          // Drive a live badge/frame with synthetic input, never device audio.
          platform.audio[id]!.add(Uint8List.fromList(List<int>.filled(160, 32)));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          switch (terminal) {
            case 'stream close':
              await platform.audio[id]!.close();
            case 'stream error':
              platform.audio[id]!.addError(StateError('synthetic stream failure'), StackTrace.current);
            case 'platform stop':
              platform.stops[id]!.add(RecordStop(reason: RecordStopReason.stop));
            case 'route pause':
              platform.states[id]!.add(RecordState.pause);
          }
          await drainRecorderEvents();
          expect(platform.live, isEmpty);
          final polls = platform.polls;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(platform.polls, polls, reason: 'Terminal capture must cancel its polling timer.');
          expect(platform.starts, 1);
          await start();
          expect(platform.starts, 2, reason: 'Only this fresh request may start a new take.');
        });
      });
    }

    test('$consumer: denied permission and capture startup errors release ownership', () async {
      await run((start, stop) async {
        platform.granted = false;
        await start();
        expect(platform.starts, 0);
        platform.granted = true;
        platform.rejectStart = true;
        if (consumer == 'voice pack') {
          await expectLater(start(), throwsStateError);
        } else {
          await start();
        }
        expect(platform.live, isEmpty);
      });
    });

    test('$consumer: failed Stop is reported and prevents another capture', () async {
      await run((start, stop) async {
        await start();
        final id = platform.live.single;
        platform.failedStops.add(id);
        await expectLater(stop(), throwsStateError);
        await start();
        expect(platform.starts, 1);
        platform.failedStops.clear();
        await stop();
        expect(platform.live, isEmpty);
      });
    });

    test('$consumer: Stop during native Start releases a late capture without restart', () async {
      await run((start, stop) async {
        platform.startGate = Completer<void>();
        final starting = start();
        await drainRecorderEvents();
        expect(platform.starts, 1);
        final stopping = stop();
        platform.startGate!.complete();
        await starting;
        await stopping;
        await drainRecorderEvents();
        expect(platform.live, isEmpty);
        expect(platform.starts, 1);
      });
    });
  }
}
