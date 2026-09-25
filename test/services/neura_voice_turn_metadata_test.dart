import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_speech_engine.dart';
import 'package:neuro_companion/services/neura_voice_turn_metadata.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 9, 25, 12);

  NeuraVoiceMetadataConsentLease lease(
    String id,
    NeuraVoiceMetadataOperation operation,
  ) {
    return NeuraVoiceMetadataConsentLease(
      id: id,
      turnId: 'turn-1',
      operations: {operation},
      issuedAtUtc: issuedAt,
      expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
      directUserGesture: true,
    );
  }

  test('builder discards transcript while retaining bounded turn signals', () {
    final builder = NeuraVoiceTurnMetadataBuilder(
      turnId: 'turn-1',
      engineId: 'fake-local',
    );
    builder.add(
      NeuraSpeechSegment(
        engineId: 'fake-local',
        text: 'private first phrase',
        isFinal: true,
        observedAtUtc: issuedAt,
        confidence: 0.8,
      ),
    );
    builder.add(
      NeuraSpeechSegment(
        engineId: 'fake-local',
        text: 'private second phrase',
        isFinal: true,
        observedAtUtc: issuedAt.add(const Duration(seconds: 2)),
        confidence: 0.6,
        pauseBefore: const Duration(milliseconds: 700),
      ),
    );
    builder.markInterruption();

    final metadata = builder.build(estimatedAffect: NeuraVoiceAffect.tense);
    expect(metadata.meanConfidence, closeTo(0.7, 0.0001));
    expect(metadata.pauseCount, 1);
    expect(metadata.interruptionCount, 1);
    expect(metadata.affectConfirmed, isFalse);
    expect(metadata.toString(), isNot(contains('private first phrase')));
  });

  test('builder rejects out-of-order segment metadata', () {
    final builder = NeuraVoiceTurnMetadataBuilder(
      turnId: 'turn-1',
      engineId: 'fake-local',
    );
    builder.add(
      NeuraSpeechSegment(
        engineId: 'fake-local',
        text: 'later',
        isFinal: true,
        observedAtUtc: issuedAt.add(const Duration(seconds: 2)),
      ),
    );

    expect(
      () => builder.add(
        NeuraSpeechSegment(
          engineId: 'fake-local',
          text: 'earlier',
          isFinal: true,
          observedAtUtc: issuedAt,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'capture, inspection, correction, and disclosure need separate leases',
    () {
      final store = NeuraVoiceTurnMetadataStore(safeModeReader: () => false);
      final metadata = NeuraVoiceTurnMetadata(
        turnId: 'turn-1',
        engineId: 'fake-local',
        observedAtUtc: issuedAt,
        speechDuration: const Duration(seconds: 2),
        pauseCount: 1,
        interruptionCount: 0,
        meanConfidence: 0.75,
        affect: NeuraVoiceAffect.tense,
        affectOrigin: NeuraVoiceAffectOrigin.onDeviceEstimate,
      );

      store.record(
        lease: lease('capture', NeuraVoiceMetadataOperation.capture),
        metadata: metadata,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      );
      final before = store.read(
        lease: lease('read-1', NeuraVoiceMetadataOperation.read),
        turnId: 'turn-1',
        nowUtc: issuedAt.add(const Duration(seconds: 2)),
      );
      expect(before?.affectConfirmed, isFalse);

      expect(
        store.correctAffect(
          lease: lease('correct', NeuraVoiceMetadataOperation.correct),
          turnId: 'turn-1',
          affect: NeuraVoiceAffect.calm,
          nowUtc: issuedAt.add(const Duration(seconds: 3)),
        ),
        isTrue,
      );
      final disclosure = store.createCloudDisclosure(
        lease: lease('disclose', NeuraVoiceMetadataOperation.discloseCloud),
        turnId: 'turn-1',
        nowUtc: issuedAt.add(const Duration(seconds: 4)),
      );

      expect(disclosure?['affect'], 'calm');
      expect(disclosure?['affect_confirmed'], isTrue);
      expect(disclosure.toString(), isNot(contains('private')));
    },
  );

  test('unconfirmed affect is withheld from fresh cloud disclosure', () {
    final store = NeuraVoiceTurnMetadataStore(safeModeReader: () => false);
    store.record(
      lease: lease('capture', NeuraVoiceMetadataOperation.capture),
      metadata: NeuraVoiceTurnMetadata(
        turnId: 'turn-1',
        engineId: 'fake-local',
        observedAtUtc: issuedAt,
        speechDuration: const Duration(seconds: 1),
        pauseCount: 0,
        interruptionCount: 0,
        affect: NeuraVoiceAffect.uncertain,
        affectOrigin: NeuraVoiceAffectOrigin.onDeviceEstimate,
      ),
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    final disclosure = store.createCloudDisclosure(
      lease: lease('disclose', NeuraVoiceMetadataOperation.discloseCloud),
      turnId: 'turn-1',
      nowUtc: issuedAt.add(const Duration(seconds: 2)),
    );

    expect(disclosure, isNot(contains('affect')));
    expect(disclosure?['affect_confirmed'], isFalse);
  });

  test('Safe Mode blocks metadata access before consuming consent', () {
    var safeMode = true;
    final store = NeuraVoiceTurnMetadataStore(safeModeReader: () => safeMode);
    final capture = lease('capture', NeuraVoiceMetadataOperation.capture);

    expect(
      () => store.record(
        lease: capture,
        metadata: NeuraVoiceTurnMetadata(
          turnId: 'turn-1',
          engineId: 'fake-local',
          observedAtUtc: issuedAt,
          speechDuration: Duration.zero,
          pauseCount: 0,
          interruptionCount: 0,
        ),
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      ),
      throwsStateError,
    );
    expect(capture.isConsumed, isFalse);

    safeMode = false;
    store.clear();
    expect(store.recordCount, 0);
  });
}
