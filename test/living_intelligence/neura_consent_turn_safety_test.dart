import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/living_intelligence/living_intelligence.dart';
import 'package:neuro_companion/persona/models/neura_audience.dart';

class _ScriptedBackend implements NeuraModelBackend {
  _ScriptedBackend({
    required this.id,
    required this.runsLocally,
    required this.available,
    this.deltas = const <NeuraModelDelta>[],
    this.afterFirstDeltaGate,
  });

  @override
  final String id;

  @override
  final bool runsLocally;

  final bool available;
  final List<NeuraModelDelta> deltas;
  final Completer<void>? afterFirstDeltaGate;

  int availabilityChecks = 0;
  int generationCalls = 0;

  @override
  Future<NeuraModelAvailability> checkAvailability() async {
    availabilityChecks += 1;
    return NeuraModelAvailability(
      state: available
          ? NeuraModelAvailabilityState.available
          : NeuraModelAvailabilityState.unavailable,
    );
  }

  @override
  Stream<NeuraModelDelta> generate({
    required NeuraModelRequest request,
    required NeuraCancellationToken cancellation,
  }) async* {
    generationCalls += 1;
    for (var index = 0; index < deltas.length; index += 1) {
      cancellation.throwIfCancelled();
      yield deltas[index];
      if (index == 0 && afterFirstDeltaGate != null) {
        await afterFirstDeltaGate!.future;
      }
    }
  }
}

void main() {
  group('Purpose-scoped cloud inference consent', () {
    test('issuance requires direct fresh approval and cloud opt-in', () {
      final registry = NeuraCloudInferenceConsentRegistry(
        safetyPolicy: NeuraLivingSafetyPolicy(
          safeModeReader: () => false,
        ),
      );

      expect(
        () => registry.issue(
          purposeId: NeuraModelPurpose.createDraft.name,
          contextCapsuleId: 'personal',
          permittedDataLabels: const <String>['visible_selection'],
          context: const NeuraSafetyContext(
            allowCloudInference: true,
          ),
        ),
        throwsStateError,
      );
      expect(
        () => registry.issue(
          purposeId: NeuraModelPurpose.createDraft.name,
          contextCapsuleId: 'personal',
          permittedDataLabels: const <String>['visible_selection'],
          context: const NeuraSafetyContext(
            directUserGesture: true,
            freshApproval: true,
          ),
        ),
        throwsStateError,
      );
    });

    test('cloud fallback requires a matching one-use permit', () async {
      final local = _ScriptedBackend(
        id: 'local',
        runsLocally: true,
        available: false,
      );
      final cloud = _ScriptedBackend(
        id: 'cloud',
        runsLocally: false,
        available: true,
        deltas: const <NeuraModelDelta>[
          NeuraModelDelta(text: 'draft', isFinal: true),
        ],
      );
      final policy = NeuraLivingSafetyPolicy(
        safeModeReader: () => false,
      );
      final consent = NeuraCloudInferenceConsentRegistry(
        safetyPolicy: policy,
      );
      final router = NeuraLocalModelRouter(
        safetyPolicy: policy,
        cloudConsentRegistry: consent,
        backends: <NeuraModelBackend>[local, cloud],
        enabled: true,
      );
      const context = NeuraSafetyContext(
        directUserGesture: true,
        freshApproval: true,
        allowCloudInference: true,
      );

      final withoutPermit = router.generate(
        NeuraModelRequest(
          purpose: NeuraModelPurpose.createDraft,
          prompt: 'Create a visible draft.',
          contextCapsuleId: 'personal',
          permittedDataLabels: const <String>['visible_selection'],
          safetyContext: context,
        ),
        cancellation: NeuraCancellationToken(),
      );
      await expectLater(withoutPermit, emitsError(isA<StateError>()));
      expect(cloud.availabilityChecks, 0);
      expect(cloud.generationCalls, 0);

      final permit = consent.issue(
        purposeId: NeuraModelPurpose.createDraft.name,
        contextCapsuleId: 'personal',
        permittedDataLabels: const <String>['visible_selection'],
        context: context,
      );
      final approvedRequest = NeuraModelRequest(
        purpose: NeuraModelPurpose.createDraft,
        prompt: 'Create a visible draft.',
        contextCapsuleId: 'personal',
        cloudConsentPermitId: permit.id,
        permittedDataLabels: const <String>['visible_selection'],
        safetyContext: context,
      );

      final approved = await router
          .generate(
            approvedRequest,
            cancellation: NeuraCancellationToken(),
          )
          .toList();
      expect(approved.single.text, 'draft');
      expect(cloud.generationCalls, 1);
      expect(
        consent.stateOf(permit.id),
        NeuraCloudInferencePermitState.consumed,
      );

      final reused = router.generate(
        approvedRequest,
        cancellation: NeuraCancellationToken(),
      );
      await expectLater(reused, emitsError(isA<StateError>()));
      expect(cloud.generationCalls, 1);
    });

    test('scope mismatch does not consume the permit', () {
      final policy = NeuraLivingSafetyPolicy(
        safeModeReader: () => false,
      );
      final registry = NeuraCloudInferenceConsentRegistry(
        safetyPolicy: policy,
      );
      const context = NeuraSafetyContext(
        directUserGesture: true,
        freshApproval: true,
        allowCloudInference: true,
      );
      final issuedAt = DateTime.utc(2026, 8, 26, 12);
      final permit = registry.issue(
        purposeId: NeuraModelPurpose.explainDecision.name,
        contextCapsuleId: 'work',
        permittedDataLabels: const <String>['decision_labels'],
        context: context,
        now: issuedAt,
      );

      final mismatch = registry.validateAndConsume(
        permitId: permit.id,
        purposeId: NeuraModelPurpose.createDraft.name,
        contextCapsuleId: 'work',
        requestedDataLabels: const <String>['decision_labels'],
        containsPrivateRecords: false,
        context: context,
        now: issuedAt.add(const Duration(minutes: 1)),
      );
      expect(mismatch.allowed, isFalse);
      expect(
        registry.stateOf(
          permit.id,
          now: issuedAt.add(const Duration(minutes: 1)),
        ),
        NeuraCloudInferencePermitState.active,
      );

      final partialScope = registry.validateAndConsume(
        permitId: permit.id,
        purposeId: NeuraModelPurpose.explainDecision.name,
        contextCapsuleId: 'work',
        requestedDataLabels: const <String>[],
        containsPrivateRecords: false,
        context: context,
        now: issuedAt.add(const Duration(minutes: 1)),
      );
      expect(partialScope.allowed, isFalse);
      expect(
        registry.stateOf(
          permit.id,
          now: issuedAt.add(const Duration(minutes: 1)),
        ),
        NeuraCloudInferencePermitState.active,
      );

      final matching = registry.validateAndConsume(
        permitId: permit.id,
        purposeId: NeuraModelPurpose.explainDecision.name,
        contextCapsuleId: 'work',
        requestedDataLabels: const <String>['decision_labels'],
        containsPrivateRecords: false,
        context: context,
        now: issuedAt.add(const Duration(minutes: 1)),
      );
      expect(matching.allowed, isTrue);
      expect(matching.grantsExecutionAuthority, isFalse);
    });

    test('private records and expired permits fail closed', () {
      final policy = NeuraLivingSafetyPolicy(
        safeModeReader: () => false,
      );
      final registry = NeuraCloudInferenceConsentRegistry(
        safetyPolicy: policy,
      );
      const context = NeuraSafetyContext(
        directUserGesture: true,
        freshApproval: true,
        allowCloudInference: true,
      );
      final issuedAt = DateTime.utc(2026, 8, 26, 12);
      final permit = registry.issue(
        purposeId: NeuraModelPurpose.summarizeVisibleContent.name,
        contextCapsuleId: 'private_vault',
        permittedDataLabels: const <String>['visible_selection'],
        context: context,
        ttl: const Duration(minutes: 1),
        now: issuedAt,
      );

      final privateDecision = registry.validateAndConsume(
        permitId: permit.id,
        purposeId: NeuraModelPurpose.summarizeVisibleContent.name,
        contextCapsuleId: 'private_vault',
        requestedDataLabels: const <String>['visible_selection'],
        containsPrivateRecords: true,
        context: context,
        now: issuedAt,
      );
      expect(privateDecision.allowed, isFalse);
      expect(
        registry.stateOf(permit.id, now: issuedAt),
        NeuraCloudInferencePermitState.active,
      );

      final expired = registry.validate(
        permitId: permit.id,
        purposeId: NeuraModelPurpose.summarizeVisibleContent.name,
        contextCapsuleId: 'private_vault',
        requestedDataLabels: const <String>['visible_selection'],
        containsPrivateRecords: false,
        context: context,
        now: issuedAt.add(const Duration(minutes: 2)),
      );
      expect(expired.allowed, isFalse);
      expect(expired.state, NeuraCloudInferencePermitState.expired);
    });
  });

  group('Conversational turn safety', () {
    test('streams display-only deltas and closes a completed turn', () async {
      final backend = _ScriptedBackend(
        id: 'local',
        runsLocally: true,
        available: true,
        deltas: const <NeuraModelDelta>[
          NeuraModelDelta(text: 'Hello '),
          NeuraModelDelta(text: 'there.', isFinal: true),
        ],
      );
      final router = NeuraLocalModelRouter(
        safetyPolicy: NeuraLivingSafetyPolicy(
          safeModeReader: () => false,
        ),
        backends: <NeuraModelBackend>[backend],
        enabled: true,
      );
      final presence = NeuraPresenceEngine(
        bindings: const NeuraPresenceBindings(),
      );
      final coordinator = NeuraConversationTurnCoordinator(
        modelRouter: router,
        presenceEngine: presence,
      );

      final deltas = await coordinator
          .startTurn(
            NeuraModelRequest(
              purpose: NeuraModelPurpose.explainDecision,
              prompt: 'Explain.',
              safetyContext: const NeuraSafetyContext(),
            ),
          )
          .toList();

      expect(deltas, hasLength(2));
      expect(deltas.every((delta) => !delta.grantsExecutionAuthority), isTrue);
      expect(deltas.last.isFinal, isTrue);
      expect(coordinator.hasActiveTurn, isFalse);
      expect(presence.state, NeuraPresenceState.idle);
    });

    test('barge-in cancels the active turn and stops speech', () async {
      final gate = Completer<void>();
      final backend = _ScriptedBackend(
        id: 'local',
        runsLocally: true,
        available: true,
        afterFirstDeltaGate: gate,
        deltas: const <NeuraModelDelta>[
          NeuraModelDelta(text: 'First part'),
          NeuraModelDelta(text: 'late output', isFinal: true),
        ],
      );
      var cancelledGeneration = 0;
      var stoppedSpeech = 0;
      var releasedAudio = 0;
      final presence = NeuraPresenceEngine(
        bindings: NeuraPresenceBindings(
          cancelGeneration: () async {
            cancelledGeneration += 1;
          },
          stopSpeech: () async {
            stoppedSpeech += 1;
          },
          releaseAudioFocus: () async {
            releasedAudio += 1;
          },
        ),
      );
      final coordinator = NeuraConversationTurnCoordinator(
        modelRouter: NeuraLocalModelRouter(
          safetyPolicy: NeuraLivingSafetyPolicy(
            safeModeReader: () => false,
          ),
          backends: <NeuraModelBackend>[backend],
          enabled: true,
        ),
        presenceEngine: presence,
      );
      final firstDelta = Completer<void>();
      final received = <NeuraTurnDelta>[];
      final subscription = coordinator
          .startTurn(
            NeuraModelRequest(
              purpose: NeuraModelPurpose.createDraft,
              prompt: 'Draft.',
              safetyContext: const NeuraSafetyContext(),
            ),
          )
          .listen((delta) {
        received.add(delta);
        if (!firstDelta.isCompleted) {
          firstDelta.complete();
        }
      });
      final completed = subscription.asFuture<void>();

      await firstDelta.future;
      expect(presence.state, NeuraPresenceState.speaking);
      await coordinator.interruptForUserSpeech(
        now: DateTime.utc(2026, 8, 26, 12),
      );
      gate.complete();
      await completed;

      expect(received, hasLength(1));
      expect(coordinator.hasActiveTurn, isFalse);
      expect(presence.state, NeuraPresenceState.interrupted);
      expect(cancelledGeneration, 1);
      expect(stoppedSpeech, 1);
      expect(releasedAudio, 1);
    });

    test('rejects unbounded or control-character output', () async {
      final oversized = _ScriptedBackend(
        id: 'oversized',
        runsLocally: true,
        available: true,
        deltas: const <NeuraModelDelta>[
          NeuraModelDelta(text: '123456', isFinal: true),
        ],
      );
      final coordinator = NeuraConversationTurnCoordinator(
        modelRouter: NeuraLocalModelRouter(
          safetyPolicy: NeuraLivingSafetyPolicy(
            safeModeReader: () => false,
          ),
          backends: <NeuraModelBackend>[oversized],
          enabled: true,
        ),
        presenceEngine: NeuraPresenceEngine(
          bindings: const NeuraPresenceBindings(),
        ),
        limits: const NeuraTurnLimits(
          maximumDeltaCharacters: 5,
          maximumTotalCharacters: 10,
        ),
      );

      await expectLater(
        coordinator.startTurn(
          NeuraModelRequest(
            purpose: NeuraModelPurpose.createDraft,
            prompt: 'Draft.',
            safetyContext: const NeuraSafetyContext(),
          ),
        ),
        emitsError(isA<StateError>()),
      );

      final controlCharacter = _ScriptedBackend(
        id: 'control',
        runsLocally: true,
        available: true,
        deltas: const <NeuraModelDelta>[
          NeuraModelDelta(text: 'bad\u0001text', isFinal: true),
        ],
      );
      final controlCoordinator = NeuraConversationTurnCoordinator(
        modelRouter: NeuraLocalModelRouter(
          safetyPolicy: NeuraLivingSafetyPolicy(
            safeModeReader: () => false,
          ),
          backends: <NeuraModelBackend>[controlCharacter],
          enabled: true,
        ),
        presenceEngine: NeuraPresenceEngine(
          bindings: const NeuraPresenceBindings(),
        ),
      );

      await expectLater(
        controlCoordinator.startTurn(
          NeuraModelRequest(
            purpose: NeuraModelPurpose.createDraft,
            prompt: 'Draft.',
            safetyContext: const NeuraSafetyContext(),
          ),
        ),
        emitsError(isA<StateError>()),
      );
    });

    test('Safe Mode becoming active stops a live model stream', () async {
      var safeMode = false;
      final gate = Completer<void>();
      final backend = _ScriptedBackend(
        id: 'local',
        runsLocally: true,
        available: true,
        afterFirstDeltaGate: gate,
        deltas: const <NeuraModelDelta>[
          NeuraModelDelta(text: 'first'),
          NeuraModelDelta(text: 'second', isFinal: true),
        ],
      );
      final router = NeuraLocalModelRouter(
        safetyPolicy: NeuraLivingSafetyPolicy(
          safeModeReader: () => safeMode,
        ),
        backends: <NeuraModelBackend>[backend],
        enabled: true,
      );
      final first = Completer<void>();
      final received = <NeuraModelDelta>[];
      final subscription = router
          .generate(
            NeuraModelRequest(
              purpose: NeuraModelPurpose.explainDecision,
              prompt: 'Explain.',
              safetyContext: const NeuraSafetyContext(),
            ),
            cancellation: NeuraCancellationToken(),
          )
          .listen((delta) {
        received.add(delta);
        if (!first.isCompleted) {
          first.complete();
        }
      });
      final completed = subscription.asFuture<void>();

      await first.future;
      safeMode = true;
      gate.complete();

      await expectLater(completed, throwsStateError);
      expect(received, hasLength(1));
    });
  });

  group('Compassionate response policy', () {
    test('keeps kindness, explanation, and autonomy non-tunable', () {
      const policy = NeuraCompassionateResponsePolicy();
      final guidance = policy.guidanceFor(
        audience: NeuraAudience.teen,
        supportSignal: NeuraSupportSignal.overwhelmed,
      );

      expect(guidance.presenceStyle, NeuraPresenceStyle.comforting);
      expect(guidance.maximumParagraphs, 2);
      expect(guidance.systemInstruction, contains('why they may help'));
      expect(guidance.systemInstruction, contains('without pressure'));
      expect(guidance.containsClinicalDiagnosis, isFalse);
      expect(guidance.maySilentlyStoreSensitiveMemory, isFalse);
      expect(guidance.grantsExecutionAuthority, isFalse);
    });

    test('child guidance uses the strictest guardrails', () {
      const policy = NeuraCompassionateResponsePolicy();
      final guidance = policy.guidanceFor(
        audience: NeuraAudience.child,
        depth: NeuraResponseDepth.detailed,
      );

      expect(guidance.maximumParagraphs, 2);
      expect(guidance.systemInstruction, contains('Never request secrets'));
      expect(guidance.systemInstruction, contains('trusted adult'));
    });

    test('quiet mode produces no proactive response budget', () {
      const policy = NeuraCompassionateResponsePolicy();
      final guidance = policy.guidanceFor(
        audience: NeuraAudience.adult,
        quietMode: true,
      );

      expect(guidance.presenceStyle, NeuraPresenceStyle.quiet);
      expect(guidance.maximumParagraphs, 0);
      expect(guidance.systemInstruction, contains('Do not speak'));
    });
  });

  test('data wipe revokes cloud permits and enters quiet mode', () async {
    final runtime = NeuraLivingIntelligenceRuntime.create(
      safeModeReader: () => false,
    );
    const context = NeuraSafetyContext(
      directUserGesture: true,
      freshApproval: true,
      allowCloudInference: true,
    );
    runtime.setEnabled(true, context: context);
    runtime.issueCloudInferencePermit(
      purpose: NeuraModelPurpose.createDraft,
      contextCapsuleId: 'personal',
      permittedDataLabels: const <String>['visible_selection'],
      context: context,
    );

    expect(runtime.status.activeCloudPermits, 1);
    await runtime.resetAfterDataWipe();

    expect(runtime.enabled, isFalse);
    expect(runtime.status.activeCloudPermits, 0);
    expect(runtime.presenceEngine.isQuiet, isTrue);
  });
}
