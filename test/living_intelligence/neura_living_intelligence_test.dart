import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/living_intelligence/living_intelligence.dart';

class _FakeBackend implements NeuraModelBackend {
  _FakeBackend({
    required this.id,
    required this.runsLocally,
    this.available = true,
  });

  @override
  final String id;

  @override
  final bool runsLocally;

  final bool available;
  int calls = 0;

  @override
  Future<NeuraModelAvailability> checkAvailability() async {
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
    calls += 1;
    cancellation.throwIfCancelled();
    yield NeuraModelDelta(
      text: '$id:${request.prompt}',
      isFinal: true,
    );
  }
}

class _TrustedVerifier implements NeuraSkillSignatureVerifier {
  const _TrustedVerifier();

  @override
  Future<bool> verify(NeuraSkillManifest manifest) async {
    return manifest.signature == 'trusted-signature';
  }
}

void main() {
  group('Living Intelligence safety policy', () {
    test('Safe Mode always wins', () {
      final policy = NeuraLivingSafetyPolicy(
        safeModeReader: () => true,
      );

      final decision = policy.evaluate(
        capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
        context: const NeuraSafetyContext(
          directUserGesture: true,
          freshApproval: true,
        ),
      );

      expect(decision.isBlocked, isTrue);
      expect(decision.grantsExecutionAuthority, isFalse);
    });

    test('unknown capabilities and money movement stay blocked', () {
      final policy = NeuraLivingSafetyPolicy(
        safeModeReader: () => false,
      );
      const context = NeuraSafetyContext(
        directUserGesture: true,
        freshApproval: true,
      );

      expect(
        policy
            .evaluate(
              capabilityId: 'not_registered',
              context: context,
            )
            .isBlocked,
        isTrue,
      );
      expect(
        policy
            .evaluate(
              capabilityId: NeuraCapabilityRegistry.moveMoney,
              context: context,
            )
            .isBlocked,
        isTrue,
      );
    });

    test('local mutations need direct fresh approval', () {
      final policy = NeuraLivingSafetyPolicy(
        safeModeReader: () => false,
      );

      final unapproved = policy.evaluate(
        capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
        context: const NeuraSafetyContext(),
        requestsMutation: true,
      );
      final approved = policy.evaluate(
        capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
        context: const NeuraSafetyContext(
          directUserGesture: true,
          freshApproval: true,
        ),
        requestsMutation: true,
      );

      expect(unapproved.requiresFreshApproval, isTrue);
      expect(approved.mayPrepare, isTrue);
      expect(approved.grantsExecutionAuthority, isFalse);
    });
  });

  group('Private Neural Core', () {
    test('routes to a local backend before cloud', () async {
      final local = _FakeBackend(
        id: 'local',
        runsLocally: true,
      );
      final cloud = _FakeBackend(
        id: 'cloud',
        runsLocally: false,
      );
      final policy = NeuraLivingSafetyPolicy(
        safeModeReader: () => false,
      );
      final router = NeuraLocalModelRouter(
        safetyPolicy: policy,
        backends: [local, cloud],
        enabled: true,
      );

      final deltas = await router
          .generate(
            NeuraModelRequest(
              purpose: NeuraModelPurpose.explainDecision,
              prompt: 'explain',
              safetyContext: const NeuraSafetyContext(
                allowCloudInference: true,
              ),
            ),
            cancellation: NeuraCancellationToken(),
          )
          .toList();

      expect(deltas.single.text, 'local:explain');
      expect(local.calls, 1);
      expect(cloud.calls, 0);
    });

    test('does not send private records to a cloud fallback', () async {
      final cloud = _FakeBackend(
        id: 'cloud',
        runsLocally: false,
      );
      final router = NeuraLocalModelRouter(
        safetyPolicy: NeuraLivingSafetyPolicy(
          safeModeReader: () => false,
        ),
        backends: [cloud],
        enabled: true,
      );

      final stream = router.generate(
        NeuraModelRequest(
          purpose: NeuraModelPurpose.createDraft,
          prompt: 'draft',
          containsPrivateRecords: true,
          safetyContext: const NeuraSafetyContext(
            allowCloudInference: true,
          ),
        ),
        cancellation: NeuraCancellationToken(),
      );

      await expectLater(
        stream,
        emitsError(isA<StateError>()),
      );
      expect(cloud.calls, 0);
    });
  });

  group('Reflex Safety Layer', () {
    test('enters Safe Mode without model reasoning', () async {
      var cancellations = 0;
      var safeModeRequests = 0;

      final layer = NeuraReflexSafetyLayer(
        bindings: NeuraReflexBindings(
          cancelGeneration: () async {
            cancellations += 1;
          },
          enterSafeMode: () async {
            safeModeRequests += 1;
          },
        ),
      );

      final result = await layer.handle('Enter Safe Mode!');

      expect(result.recognized, isTrue);
      expect(result.command, NeuraReflexCommand.enterSafeMode);
      expect(cancellations, 1);
      expect(safeModeRequests, 1);
    });
  });

  group('Trust Lens', () {
    test('stores derived labels and never grants authority', () {
      const lens = NeuraTrustLens();
      final receipt = lens.build(
        capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
        intentSummary: 'Prepare one reversible local quest.',
        evidenceLabels: const ['direct_user_request'],
        excludedSources: const ['journal_text', 'therapy_text'],
        alternatives: const ['Do nothing', 'Open the quest screen'],
        confidence: 0.8,
        reversible: true,
        approvalMode: NeuraApprovalMode.everyTime,
        undoDescription: 'Remove the created quest.',
      );

      expect(receipt.grantsExecutionAuthority, isFalse);
      expect(receipt.excludedSources, contains('journal_text'));
      expect(receipt.confidence, 0.8);
    });

    test('rejects raw personal content in evidence labels', () {
      const lens = NeuraTrustLens();

      expect(
        () => lens.build(
          capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
          intentSummary: 'Explain a suggestion.',
          evidenceLabels: const ['journal: private sentence'],
          excludedSources: const ['messages'],
          alternatives: const ['Dismiss'],
          confidence: 0.5,
          reversible: true,
          approvalMode: NeuraApprovalMode.none,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Context Capsules', () {
    test('cross-capsule transfers require explicit approval', () {
      final registry = NeuraContextCapsuleRegistry();

      final denied = registry.evaluateTransfer(
        source: NeuraContextCapsuleKind.personal,
        destination: NeuraContextCapsuleKind.work,
        category: NeuraCapsuleDataCategory.localQuests,
        directUserGesture: false,
        freshApproval: false,
      );
      final approved = registry.evaluateTransfer(
        source: NeuraContextCapsuleKind.personal,
        destination: NeuraContextCapsuleKind.work,
        category: NeuraCapsuleDataCategory.localQuests,
        directUserGesture: true,
        freshApproval: true,
      );

      expect(denied.allowed, isFalse);
      expect(approved.allowed, isTrue);
    });

    test('Kids context refuses adult private data', () {
      final registry = NeuraContextCapsuleRegistry();

      final decision = registry.evaluateTransfer(
        source: NeuraContextCapsuleKind.privateVault,
        destination: NeuraContextCapsuleKind.kids,
        category: NeuraCapsuleDataCategory.privateRecords,
        directUserGesture: true,
        freshApproval: true,
      );

      expect(decision.allowed, isFalse);
    });
  });

  group('Signed Skill Capsules', () {
    test('accepts only a signed, declared, safe manifest', () async {
      final validator = NeuraSignedSkillValidator(
        signatureVerifier: const _TrustedVerifier(),
      );
      final valid = NeuraSkillManifest(
        id: 'neura.ritual_builder',
        version: '1.0.0',
        capabilities: const [
          NeuraCapabilityRegistry.surfaceSuggestion,
        ],
        privateDataClasses: const ['ritual_preferences'],
        permissions: const [],
        networkPolicy: NeuraSkillNetworkPolicy.none,
        signature: 'trusted-signature',
      );
      final invalid = NeuraSkillManifest(
        id: 'neura.bad_skill',
        version: '1.0.0',
        capabilities: const ['unknown_capability'],
        privateDataClasses: const [],
        permissions: const ['powershell'],
        networkPolicy: NeuraSkillNetworkPolicy.none,
        signature: 'trusted-signature',
      );

      expect((await validator.validate(valid)).accepted, isTrue);
      expect((await validator.validate(invalid)).accepted, isFalse);
    });

    test('quarantines repeatedly crashing skills', () {
      final health = NeuraSkillHealthRegistry(
        quarantineThreshold: 2,
      );

      expect(health.recordCrash('neura.test').quarantined, isFalse);
      expect(health.recordCrash('neura.test').quarantined, isTrue);
    });
  });

  group('Presence Engine 2.0', () {
    test('barge-in stops speech and guards the microphone', () async {
      var stopped = 0;
      final engine = NeuraPresenceEngine(
        bindings: NeuraPresenceBindings(
          stopSpeech: () async {
            stopped += 1;
          },
        ),
      );
      final now = DateTime.utc(2026, 8, 25, 12);

      engine.beginSpeaking();
      await engine.interruptForUserSpeech(now: now);

      expect(engine.state, NeuraPresenceState.interrupted);
      expect(engine.interruptionAcknowledgement, 'I stopped. Go ahead.');
      expect(stopped, 1);
      expect(engine.canOpenMicrophone(now: now), isFalse);
      expect(
        engine.canOpenMicrophone(
          now: now.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });
  });

  group('Future Paths Simulator', () {
    test('produces five non-executable alternatives', () {
      const simulator = NeuraFuturePathsSimulator();
      final paths = simulator.simulate(
        const [
          NeuraPlanStep(
            id: 'safe',
            title: 'Safe step',
            estimatedDuration: Duration(minutes: 5),
            effort: 2,
            cost: 0,
            risk: 0.1,
            reversible: true,
          ),
          NeuraPlanStep(
            id: 'fast',
            title: 'Fast external step',
            estimatedDuration: Duration(minutes: 1),
            effort: 1,
            cost: 2,
            risk: 0.6,
            reversible: false,
            hasExternalEffect: true,
          ),
        ],
      );

      expect(paths, hasLength(5));
      expect(paths.every((path) => !path.executable), isTrue);
      expect(paths.any((path) => path.requiresApproval), isTrue);
    });
  });

  group('Self-Healing Runtime 2.0', () {
    test('promotes a passing canary and rolls back a failure', () {
      final runtime = NeuraSelfHealingRuntime();

      final candidateSlot = runtime.installCandidate(
        const NeuraReleaseCandidate(
          version: '1.5.0',
          signatureVerified: true,
          checksumVerified: true,
        ),
      );
      final promoted = runtime.evaluateCanary(
        candidateSlot: candidateSlot,
        result: const NeuraCanaryResult(
          firstFrameRendered: true,
          runtimePayloadComplete: true,
          launchSentinelMatched: true,
        ),
      );

      expect(promoted.promoted, isTrue);
      expect(runtime.activeSlot, candidateSlot);

      final failedSlot = runtime.installCandidate(
        const NeuraReleaseCandidate(
          version: '1.5.1',
          signatureVerified: true,
          checksumVerified: true,
        ),
      );
      final rejected = runtime.evaluateCanary(
        candidateSlot: failedSlot,
        result: const NeuraCanaryResult(
          firstFrameRendered: false,
          runtimePayloadComplete: true,
          launchSentinelMatched: false,
        ),
      );

      expect(rejected.promoted, isFalse);
      expect(runtime.activeSlot, candidateSlot);
    });
  });

  group('Android intelligence integration', () {
    test('allowlists safe surfaces and blocks unknown functions', () {
      const bridge = NeuraAndroidIntelligenceBridge();
      const context = NeuraSafetyContext(
        directUserGesture: true,
      );

      final safe = bridge.evaluate(
        functionId: NeuraAndroidIntelligenceBridge.openNeura,
        context: context,
        safeModeActive: false,
      );
      final blocked = bridge.evaluate(
        functionId: 'move_money',
        context: context,
        safeModeActive: false,
      );

      expect(safe.allowed, isTrue);
      expect(safe.grantsExecutionAuthority, isFalse);
      expect(blocked.allowed, isFalse);
    });
  });

  group('Encrypted Device Continuity', () {
    test('revoked devices cannot apply encrypted envelopes', () {
      final registry = NeuraDeviceContinuityRegistry();
      const category = NeuraContinuityCategory.localQuests;
      final policy = NeuraDeviceSyncPolicy(
        allowedCategories: const [category],
      );

      registry.pairDevice(
        identity: const NeuraDeviceIdentity(
          deviceId: 'windows',
          displayName: 'Windows',
          publicKeyFingerprint: 'windows-key',
        ),
        policy: policy,
        directUserGesture: true,
        fingerprintVerified: true,
      );
      registry.pairDevice(
        identity: const NeuraDeviceIdentity(
          deviceId: 'android',
          displayName: 'Android',
          publicKeyFingerprint: 'android-key',
        ),
        policy: policy,
        directUserGesture: true,
        fingerprintVerified: true,
      );

      final envelope = NeuraContinuityEnvelope(
        senderDeviceId: 'windows',
        recipientDeviceId: 'android',
        category: category,
        sequence: 1,
        cipherSuite: 'platform-authenticated-encryption',
        ciphertext: const [1, 2, 3],
        nonce: const [4, 5],
        authenticationTag: const [6, 7],
      );

      expect(registry.validateEnvelope(envelope).allowed, isTrue);

      registry.revokeDevice('windows');
      final nextEnvelope = NeuraContinuityEnvelope(
        senderDeviceId: 'windows',
        recipientDeviceId: 'android',
        category: category,
        sequence: 2,
        cipherSuite: 'platform-authenticated-encryption',
        ciphertext: const [8],
        nonce: const [9],
        authenticationTag: const [10],
      );

      expect(registry.validateEnvelope(nextEnvelope).allowed, isFalse);
    });
  });

  group('Living Intelligence runtime', () {
    test('is opt-in and cannot enable while Safe Mode is active', () {
      final runtime = NeuraLivingIntelligenceRuntime.create(
        safeModeReader: () => true,
      );

      expect(runtime.enabled, isFalse);
      expect(
        () => runtime.setEnabled(
          true,
          context: const NeuraSafetyContext(),
        ),
        throwsStateError,
      );
    });
  });
}
