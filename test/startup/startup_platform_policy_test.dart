import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/main.dart' as neura_main;
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/notifications/neura_notifications_service.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/ambient_listening_service.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_swarm_policy.dart';
import 'package:neuro_companion/services/neura_swarm_service.dart';
import 'package:neuro_companion/services/neura_swarm_service_stub.dart'
    as web_swarm;
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/services/neura_voice_pack.dart';
import 'package:neuro_companion/services/wake_word_listener_service.dart';
import 'package:neuro_companion/startup/neura_startup_coordinator.dart';
import 'package:neuro_companion/src/modules/settings/settings.dart';

void main() {
  group('startup platform policy', () {
    test('window manager is limited to its supported desktop targets', () {
      expect(
        neura_main.supportsWindowManagerPlus(
          platform: TargetPlatform.windows,
          isWeb: false,
        ),
        isTrue,
      );
      expect(
        neura_main.supportsWindowManagerPlus(
          platform: TargetPlatform.macOS,
          isWeb: false,
        ),
        isTrue,
      );

      for (final platform in TargetPlatform.values) {
        if (platform != TargetPlatform.windows &&
            platform != TargetPlatform.macOS) {
          expect(
            neura_main.supportsWindowManagerPlus(
              platform: platform,
              isWeb: false,
            ),
            isFalse,
            reason: '$platform must not initialize window_manager_plus',
          );
        }
        expect(
          neura_main.supportsWindowManagerPlus(
            platform: platform,
            isWeb: true,
          ),
          isFalse,
          reason: 'web must never initialize window_manager_plus',
        );
      }
    });

    test('native swarm is advertised only for Windows', () {
      for (final platform in TargetPlatform.values) {
        expect(
          supportsNativeNeuraSwarm(platform: platform, isWeb: false),
          platform == TargetPlatform.windows,
        );
        expect(
          supportsNativeNeuraSwarm(platform: platform, isWeb: true),
          isFalse,
        );
      }
    });

    test('normal startup keeps optional native audio lazy', () {
      expect(kNativeAudioStartupIsLazy, isTrue);
    });

    test('native swarm startup requires explicit foreground enablement', () {
      expect(
        shouldInitializeNativeNeuraSwarm(
          platform: TargetPlatform.windows,
          isWeb: false,
          safeMode: false,
          hasProviderCredential: true,
          explicitlyEnabled: false,
        ),
        isFalse,
      );
      expect(
        shouldInitializeNativeNeuraSwarm(
          platform: TargetPlatform.windows,
          isWeb: false,
          safeMode: false,
          hasProviderCredential: true,
          explicitlyEnabled: true,
        ),
        isTrue,
      );
      expect(
        shouldInitializeNativeNeuraSwarm(
          platform: TargetPlatform.windows,
          isWeb: false,
          safeMode: false,
          hasProviderCredential: false,
          explicitlyEnabled: true,
        ),
        isFalse,
      );
      expect(
        shouldInitializeNativeNeuraSwarm(
          platform: TargetPlatform.windows,
          isWeb: false,
          safeMode: true,
          hasProviderCredential: true,
          explicitlyEnabled: true,
        ),
        isFalse,
      );
      expect(
        shouldInitializeNativeNeuraSwarm(
          platform: TargetPlatform.macOS,
          isWeb: false,
          safeMode: false,
          hasProviderCredential: true,
          explicitlyEnabled: true,
        ),
        isFalse,
      );
      expect(
        shouldInitializeNativeNeuraSwarm(
          platform: TargetPlatform.windows,
          isWeb: true,
          safeMode: false,
          hasProviderCredential: true,
          explicitlyEnabled: true,
        ),
        isFalse,
      );
    });

    test('Supabase session is read only after successful initialization', () {
      expect(
        shouldInspectSupabaseSession(
          safeMode: false,
          configured: true,
          initialized: true,
        ),
        isTrue,
      );
      expect(
        shouldInspectSupabaseSession(
          safeMode: false,
          configured: true,
          initialized: false,
        ),
        isFalse,
      );
      expect(
        shouldInspectSupabaseSession(
          safeMode: true,
          configured: true,
          initialized: true,
        ),
        isFalse,
      );
      expect(
        shouldInspectSupabaseSession(
          safeMode: false,
          configured: false,
          initialized: true,
        ),
        isFalse,
      );
    });

    test('mascot is advertised only for Windows', () {
      for (final platform in TargetPlatform.values) {
        expect(
          supportsNeuraMascot(platform: platform, isWeb: false),
          platform == TargetPlatform.windows,
        );
        expect(
          supportsNeuraMascot(platform: platform, isWeb: true),
          isFalse,
        );
      }
    });

    test('cloud settings routes stay offline in Safe Mode', () {
      expect(
        cloudSettingsRoutesAllowed(configured: true, safeMode: false),
        isTrue,
      );
      expect(
        cloudSettingsRoutesAllowed(configured: true, safeMode: true),
        isFalse,
      );
      expect(
        cloudSettingsRoutesAllowed(configured: false, safeMode: false),
        isFalse,
      );
    });

    test('web swarm fallback exposes no fake native capability', () async {
      final service = web_swarm.NeuraSwarmService.instance;
      await expectLater(
        service.init(
          'not-a-real-key',
          approval: NeuraSwarmApproval.grantFromVisibleConfirmation(),
          foreground: true,
        ),
        throwsUnsupportedError,
      );

      final outcome = await service.reviewAndExtract(
        transcript: 'local transcript',
        draftReply: 'local draft',
        userMessage: 'local message',
        approval: NeuraSwarmApproval.grantFromVisibleConfirmation(),
        foreground: true,
      );
      expect(outcome.concernNote, isNull);
      expect(outcome.facts, isEmpty);
    });
  });

  group('Safe Mode cloud policy', () {
    late bool originalSafeMode;
    late bool originalRestartRequired;

    setUp(() {
      originalSafeMode = SafeBoot.instance.safeMode.value;
      originalRestartRequired = SafeBoot.instance.restartRequired.value;
    });

    tearDown(() {
      SafeBoot.instance.safeMode.value = originalSafeMode;
      SafeBoot.instance.restartRequired.value = originalRestartRequired;
    });

    test('blocks cloud requests without deleting configuration', () {
      final configuredBefore = NeuraAiService.instance.isConfigured;
      SafeBoot.instance.safeMode.value = false;
      expect(NeuraAiService.instance.cloudRequestsAllowed, isTrue);

      SafeBoot.instance.safeMode.value = true;
      expect(NeuraAiService.instance.cloudRequestsAllowed, isFalse);
      expect(NeuraAiService.instance.isConfigured, configuredBefore);
    });

    test('one-shot generation refuses before any network request', () async {
      SafeBoot.instance.safeMode.value = true;

      await expectLater(
        NeuraAiService.instance.completeOnce(
          'This must remain local.',
          agentId: 'general',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Safe Mode'),
          ),
        ),
      );
    });

    test('streamed generation refuses before any network request', () async {
      SafeBoot.instance.safeMode.value = true;

      await expectLater(
        NeuraAiService.instance.streamReply(
          const [
            NeuraChatTurn(isUser: true, text: 'Keep this offline.'),
          ],
        ).drain<void>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Safe Mode'),
          ),
        ),
      );
    });

    test('direct native activation calls are safe no-ops', () async {
      SafeBoot.instance.safeMode.value = true;

      expect(AmbientListeningService.instance.captureAllowed, isFalse);
      await AmbientListeningService.instance.start();
      await AmbientListeningService.instance.greetAndStartListening();

      expect(WakeWordListenerService.instance.listeningAllowed, isFalse);
      await WakeWordListenerService.instance.start();
      await WakeWordListenerService.instance.resume();

      expect(NeuraNotificationsService.instance.deliveryAllowed, isFalse);
      await NeuraNotificationsService.instance.init();
      await NeuraNotificationsService.instance.scheduleDailyMoodNudge(
        const TimeOfDay(hour: 9, minute: 0),
      );

      expect(NeuraTtsService.instance.playbackAllowed, isFalse);
      await NeuraTtsService.instance.warmUp();
      await NeuraTtsService.instance.speak('This must not reach native TTS.');
      expect(await NeuraTtsService.instance.availableVoices(), isEmpty);

      expect(NeuraVoicePack.I.audioAllowed, isFalse);
      await NeuraVoicePack.I.init(enableMic: true);
      await NeuraVoicePack.I.startMic();
      await NeuraVoicePack.I.playAsset('must-not-play.wav');

      final approval =
          NeuraSwarmApproval.grantFromVisibleConfirmation();
      await expectLater(
        NeuraSwarmService.instance.init(
          'not-a-real-key',
          approval: approval,
          foreground: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Safe Mode'),
          ),
        ),
      );
      expect(approval.isConsumed, isFalse);
    });

    test('clearing Safe Mode is latched until the next launch', () async {
      SafeBoot.instance.safeMode.value = true;
      SafeBoot.instance.restartRequired.value = false;

      await SafeBoot.instance.clearSafeMode();

      expect(SafeBoot.instance.safeMode.value, isTrue);
      expect(SafeBoot.instance.restartRequired.value, isTrue);
      expect(NeuraAiService.instance.cloudRequestsAllowed, isFalse);
    });
  });
}
