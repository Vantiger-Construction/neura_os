import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/persona/models/neura_audience.dart';
import 'package:neuro_companion/persona/models/neura_persona_preset.dart';
import 'package:neuro_companion/persona/services/neura_persona_service.dart';
import 'package:neuro_companion/persona/services/neura_prompt_builder.dart';
import 'package:neuro_companion/profiles/local_profile_service.dart';
import 'package:neuro_companion/profiles/local_profile_gate.dart';
import 'package:neuro_companion/profiles/local_profile_workspace.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_cloud_transaction.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/services/neura_model_credentials.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_model_stream.dart';
import 'package:neuro_companion/services/neura_model_types.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/services/neura_local_speech_input.dart';
import 'package:neuro_companion/services/neura_speech_to_text_service.dart';
import 'package:neuro_companion/services/ambient_listening_service.dart';
import 'package:neuro_companion/services/wake_word_listener_service.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/companion_memory_fixture.dart';

class _Credentials implements NeuraModelCredentialStorage {
  final _values = <String, String>{};
  @override
  Future<String?> read({required String key}) async => _values[key];
  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}

class _Cloud extends NeuraModelStreamTransport {
  _Cloud() : super(NeuraModelProvider.openAi);
  int calls = 0;
  final prompts = <String>[];
  final toolCounts = <int>[];
  @override
  Stream<NeuraStreamEvent> stream(
      {required String apiKey,
      required String systemPrompt,
      required List<Map<String, dynamic>> messages,
      required List<Map<String, dynamic>> tools,
      required NeuraGenerationCancel cancel,
      required NeuraCloudTransactionEnvelope transaction,
      int maxTokens = 2048}) async* {
    calls++;
    prompts.add(systemPrompt);
    toolCounts.add(tools.length);
    final reply = systemPrompt.contains('Bring high energy')
        ? 'Synthetic playful response.'
        : 'Synthetic calm response.';
    yield NeuraTextDelta(provider, reply);
    yield NeuraTurnComplete(provider, [
      {'type': 'text', 'text': reply}
    ]);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real persona, chat and wipe paths isolate two synthetic people',
      (tester) async {
    final fixture = await tester.runAsync(CompanionMemoryFixture.create);
    final disk = fixture!.disk;
    final service = LocalProfileService.instance;
    await tester.runAsync(() async {
      await fixture.seed('Synthetic installation-owner secret');
      await NeuraPrefsCache.prefs.setString('neura_current_mood_v1', 'tired');
    });
    final oldGrant = fixture.grant(CompanionMemoryUse.prompt);
    final credentials = NeuraModelCredentials.forTesting(_Credentials());
    await credentials.save(
        NeuraModelProvider.openAi, 'sk-openai-test-key-1234567890');
    final cloud = _Cloud();
    final payloads = <Map<String, dynamic>>[];
    const channel = MethodChannel('neura/engine_synthetic_session');
    Completer<Object?>? delayed;
    var modelId = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'beginOllama') {
        payloads
            .add(jsonDecode(call.arguments as String) as Map<String, dynamic>);
        return ++modelId;
      }
      if (call.method == 'pollOllama') {
        return delayed?.future ?? 'Synthetic local response.';
      }
      return null;
    });
    addTearDown(() =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final ollama = NeuraOllamaChat(supported: true);
    addTearDown(ollama.dispose);
    final ai = NeuraAiService.forTesting(
        modelRouter: NeuraSecureModelRouter(
            credentials: credentials, streamTransports: [cloud]),
        configuredReader: () => true,
        ollama: ollama);
    await tester.pumpWidget(const MaterialApp(
        home: LocalProfileGate(
            child: Text('Synthetic legacy installation data'))));
    expect(find.text('Synthetic legacy installation data'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await service.enable(directUserGesture: true), isTrue);
      for (final entry in [
        ('Alex', NeuraPersonaPreset.calm),
        ('Blair', NeuraPersonaPreset.playful)
      ]) {
        expect(
            await service.create(
                label: entry.$1,
                persona: entry.$2.profile,
                audience: NeuraAudience.adult,
                directUserGesture: true),
            isTrue);
      }
    });
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Synthetic legacy installation data'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(oldGrant.requireCurrent,
        throwsA(isA<EncryptedMemoryPolicyViolation>()));
    expect(() => fixture.grant(CompanionMemoryUse.prompt),
        throwsA(isA<EncryptedMemoryPolicyViolation>()));
    expect(NeuraSpeechToTextService.instance.listeningAllowed, isFalse);
    expect(AmbientListeningService.instance.captureAllowed, isFalse);
    expect(WakeWordListenerService.instance.listeningAllowed, isFalse);
    expect(await NeuraLocalSpeechInput.instance.startRecording(), isFalse);
    expect(disk.platformCalls, isEmpty);
    final alex = service.profiles.first;
    final blair = service.profiles.last;
    NeuraMotion.instance.start();
    addTearDown(NeuraMotion.instance.stop);
    final prompts = <String>[];
    final replies = <String>[];
    var approvals = 0;
    for (final profile in [alex, blair]) {
      await tester
          .runAsync(() => service.select(profile.id, directUserGesture: true));
      prompts.add(await NeuraPromptBuilder.instance.buildSystemMessage());
      expect(NeuraPersonaService.instance.current.toMap(),
          profile.persona.toMap());
      expect(NeuraMotion.instance.engine.personaEnergy, profile.persona.energy);
      final reply = await ai.streamReply(
          const [NeuraChatTurn(isUser: true, text: 'Help me start a task')],
          requestCloudApproval: (_) async {
        approvals++;
        return true;
      }).join();
      replies.add(reply);
      await expectLater(
          ai.streamReply(const [NeuraChatTurn(isUser: true, text: 'Try again')],
              requestCloudApproval: (_) async {
            approvals++;
            return false;
          }).toList(),
          throwsA(isA<NeuraCloudApprovalDenied>()));
    }
    expect(prompts[0], isNot(prompts[1]));
    expect(
        replies, ['Synthetic calm response.', 'Synthetic playful response.']);
    expect(approvals, 4);
    expect(cloud.calls, 2);
    expect(cloud.toolCounts, [0, 0]);
    expect(cloud.prompts.join(),
        isNot(contains('Synthetic installation-owner secret')));
    expect(prompts.last,
        contains('Bring high energy')); // stored tired mood was excluded
    await expectLater(
        ai.streamReply(const [NeuraChatTurn(isUser: true, text: 'Read notes')],
            includePermittedMemory: true,
            memoryPermission: oldGrant,
            localOllama: true).toList(),
        throwsStateError);

    // A delayed native result must not reach the next profile.
    delayed = Completer<Object?>();
    final lateReply = ai.streamReply(
        const [NeuraChatTurn(isUser: true, text: 'Old synthetic turn')],
        localOllama: true).toList();
    final rejected =
        expectLater(lateReply, throwsA(isA<NeuraGenerationCancelled>()));
    await tester.pump();
    await tester
        .runAsync(() => service.select(alex.id, directUserGesture: true));
    delayed.complete('Late private-looking synthetic output');
    delayed = null;
    await tester.pump(const Duration(milliseconds: 200));
    await rejected;
    await tester
        .pumpWidget(MaterialApp(home: LocalProfileWorkspace(aiService: ai)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
        find.byType(TextField), 'Alex synthetic session text');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Alex synthetic session text'), findsOneWidget);
    await tester.tap(find.byTooltip('End chat and switch profile'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Alex synthetic session text'), findsNothing);
    final switched = service.select(blair.id, directUserGesture: true);
    var didSwitch = false;
    unawaited(switched.then((value) {
      didSwitch = value;
    }));
    for (var i = 0; i < 30 && !didSwitch; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(didSwitch, isTrue);
    await switched;
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Alex synthetic session text'), findsNothing);
    expect(find.text('Use local Ollama'), findsOneWidget);
    expect(find.text('Neura · Blair'), findsOneWidget);
    expect(find.byTooltip('Microphone'), findsNothing);
    // An approval dialog cannot survive an external session boundary.
    await tester.tap(find.byType(SwitchListTile));
    await tester.enterText(find.byType(TextField), 'Cloud preview for Blair');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Approve once'), findsOneWidget);
    final priorCalls = cloud.calls;
    await tester.runAsync(service.lock);
    await tester.pump(const Duration(milliseconds: 250));
    expect(cloud.calls, priorCalls);
    expect(find.text('Choose a local profile'), findsOneWidget);
    expect(find.textContaining('Cloud preview for Blair'), findsNothing);
    NeuraMotion.instance.stop();
    // Central full-data-wipe guarantee, not only the profile helper.
    await tester
        .runAsync(() => disk.run(NeuraDataWipeService.wipeAllLocalData));
    expect(service.active, isNull);
    expect(service.profiles, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Alex'), findsNothing);
    expect(find.text('Blair'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(NeuraPrefsCache.prefs.getString(LocalProfileService.storageKey),
        isNull);
    expect(disk.secrets['neura.memoryGraph.seed.v2'], isNull);
    expect(await service.select(alex.id, directUserGesture: true), isFalse);
    expect(SafeBoot.instance.safeMode.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
