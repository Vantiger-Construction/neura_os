import 'neura_speech_engine.dart';

enum NeuraVoiceMetadataOperation { capture, read, correct, discloseCloud }

enum NeuraVoiceAffect { calm, upbeat, tense, lowEnergy, uncertain }

enum NeuraVoiceAffectOrigin { unavailable, onDeviceEstimate, userCorrected }

final class NeuraVoiceMetadataConsentLease {
  NeuraVoiceMetadataConsentLease({
    required this.id,
    required this.turnId,
    required Set<NeuraVoiceMetadataOperation> operations,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required this.directUserGesture,
  }) : operations = Set.unmodifiable(operations) {
    _requireId(id, 'lease_id');
    _requireId(turnId, 'turn_id');
    if (this.operations.isEmpty) {
      throw const FormatException('Voice metadata operations are empty.');
    }
    if (!issuedAtUtc.isUtc ||
        !expiresAtUtc.isUtc ||
        !expiresAtUtc.isAfter(issuedAtUtc) ||
        expiresAtUtc.difference(issuedAtUtc) > const Duration(minutes: 15)) {
      throw const FormatException('Invalid voice metadata lease time.');
    }
  }

  final String id;
  final String turnId;
  final Set<NeuraVoiceMetadataOperation> operations;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final bool directUserGesture;
  bool _consumed = false;

  bool authorizes(
    String requestedTurnId,
    NeuraVoiceMetadataOperation operation,
    DateTime nowUtc,
  ) {
    return !_consumed &&
        directUserGesture &&
        requestedTurnId == turnId &&
        operations.contains(operation) &&
        nowUtc.isUtc &&
        !nowUtc.isBefore(issuedAtUtc) &&
        nowUtc.isBefore(expiresAtUtc);
  }

  void consume(
    String requestedTurnId,
    NeuraVoiceMetadataOperation operation,
    DateTime nowUtc,
  ) {
    if (!authorizes(requestedTurnId, operation, nowUtc)) {
      throw StateError('Voice metadata consent is not authorized.');
    }
    _consumed = true;
  }

  bool get isConsumed => _consumed;
}

final class NeuraVoiceTurnMetadata {
  NeuraVoiceTurnMetadata({
    required this.turnId,
    required this.engineId,
    required this.observedAtUtc,
    required this.speechDuration,
    required this.pauseCount,
    required this.interruptionCount,
    this.meanConfidence,
    this.affect,
    this.affectOrigin = NeuraVoiceAffectOrigin.unavailable,
    this.affectConfirmed = false,
  }) {
    _requireId(turnId, 'turn_id');
    _requireId(engineId, 'engine_id');
    if (!observedAtUtc.isUtc ||
        speechDuration.isNegative ||
        pauseCount < 0 ||
        interruptionCount < 0) {
      throw const FormatException('Invalid voice turn metadata.');
    }
    if (meanConfidence != null &&
        (!meanConfidence!.isFinite ||
            meanConfidence! < 0 ||
            meanConfidence! > 1)) {
      throw const FormatException('Invalid mean confidence.');
    }
    if (affect == null &&
        affectOrigin != NeuraVoiceAffectOrigin.unavailable) {
      throw const FormatException('Affect origin requires an affect value.');
    }
    if (affectConfirmed &&
        affectOrigin != NeuraVoiceAffectOrigin.userCorrected) {
      throw const FormatException('Only user-corrected affect is confirmed.');
    }
  }

  final String turnId;
  final String engineId;
  final DateTime observedAtUtc;
  final Duration speechDuration;
  final int pauseCount;
  final int interruptionCount;
  final double? meanConfidence;
  final NeuraVoiceAffect? affect;
  final NeuraVoiceAffectOrigin affectOrigin;
  final bool affectConfirmed;

  NeuraVoiceTurnMetadata correctAffect(NeuraVoiceAffect corrected) {
    return NeuraVoiceTurnMetadata(
      turnId: turnId,
      engineId: engineId,
      observedAtUtc: observedAtUtc,
      speechDuration: speechDuration,
      pauseCount: pauseCount,
      interruptionCount: interruptionCount,
      meanConfidence: meanConfidence,
      affect: corrected,
      affectOrigin: NeuraVoiceAffectOrigin.userCorrected,
      affectConfirmed: true,
    );
  }
}

/// Builds metadata without retaining transcript text.
final class NeuraVoiceTurnMetadataBuilder {
  NeuraVoiceTurnMetadataBuilder({
    required this.turnId,
    required this.engineId,
  });

  final String turnId;
  final String engineId;
  final List<double> _confidences = [];
  DateTime? _firstObservedAtUtc;
  DateTime? _lastObservedAtUtc;
  var _pauseCount = 0;
  var _interruptionCount = 0;

  void add(NeuraSpeechSegment segment) {
    if (segment.engineId != engineId) {
      throw StateError('Speech segment engine does not match this turn.');
    }
    if (_lastObservedAtUtc != null &&
        segment.observedAtUtc.isBefore(_lastObservedAtUtc!)) {
      throw StateError('Speech segment timestamps must be monotonic.');
    }
    _firstObservedAtUtc ??= segment.observedAtUtc;
    _lastObservedAtUtc = segment.observedAtUtc;
    if (segment.pauseBefore >= const Duration(milliseconds: 500)) {
      _pauseCount++;
    }
    if (segment.confidence != null) {
      _confidences.add(segment.confidence!);
    }
  }

  void markInterruption() => _interruptionCount++;

  NeuraVoiceTurnMetadata build({
    NeuraVoiceAffect? estimatedAffect,
  }) {
    final first = _firstObservedAtUtc;
    final last = _lastObservedAtUtc;
    if (first == null || last == null) {
      throw StateError('Cannot build empty voice metadata.');
    }
    final mean = _confidences.isEmpty
        ? null
        : _confidences.reduce((a, b) => a + b) / _confidences.length;
    return NeuraVoiceTurnMetadata(
      turnId: turnId,
      engineId: engineId,
      observedAtUtc: first,
      speechDuration:
          last.isAfter(first) ? last.difference(first) : Duration.zero,
      pauseCount: _pauseCount,
      interruptionCount: _interruptionCount,
      meanConfidence: mean,
      affect: estimatedAffect,
      affectOrigin: estimatedAffect == null
          ? NeuraVoiceAffectOrigin.unavailable
          : NeuraVoiceAffectOrigin.onDeviceEstimate,
    );
  }
}

/// Process-local, consent-scoped metadata store.
///
/// It has no serialization API and stores no transcript. Safe Mode blocks all
/// optional access. Cloud disclosure requires its own fresh single-use lease.
final class NeuraVoiceTurnMetadataStore {
  NeuraVoiceTurnMetadataStore({required bool Function() safeModeReader})
      : _safeModeReader = safeModeReader;

  final bool Function() _safeModeReader;
  final Map<String, NeuraVoiceTurnMetadata> _records = {};

  int get recordCount => _records.length;

  void record({
    required NeuraVoiceMetadataConsentLease lease,
    required NeuraVoiceTurnMetadata metadata,
    required DateTime nowUtc,
  }) {
    _requireAvailable();
    lease.consume(
      metadata.turnId,
      NeuraVoiceMetadataOperation.capture,
      nowUtc,
    );
    if (_records.containsKey(metadata.turnId)) {
      throw StateError('Voice metadata turn already exists.');
    }
    _records[metadata.turnId] = metadata;
  }

  NeuraVoiceTurnMetadata? read({
    required NeuraVoiceMetadataConsentLease lease,
    required String turnId,
    required DateTime nowUtc,
  }) {
    _requireAvailable();
    lease.consume(turnId, NeuraVoiceMetadataOperation.read, nowUtc);
    return _records[turnId];
  }

  bool correctAffect({
    required NeuraVoiceMetadataConsentLease lease,
    required String turnId,
    required NeuraVoiceAffect affect,
    required DateTime nowUtc,
  }) {
    _requireAvailable();
    lease.consume(turnId, NeuraVoiceMetadataOperation.correct, nowUtc);
    final current = _records[turnId];
    if (current == null) return false;
    _records[turnId] = current.correctAffect(affect);
    return true;
  }

  Map<String, Object?>? createCloudDisclosure({
    required NeuraVoiceMetadataConsentLease lease,
    required String turnId,
    required DateTime nowUtc,
  }) {
    _requireAvailable();
    lease.consume(
      turnId,
      NeuraVoiceMetadataOperation.discloseCloud,
      nowUtc,
    );
    final metadata = _records[turnId];
    if (metadata == null) return null;
    return {
      'turn_id': metadata.turnId,
      'engine_id': metadata.engineId,
      'observed_at_utc': metadata.observedAtUtc.toIso8601String(),
      'speech_duration_ms': metadata.speechDuration.inMilliseconds,
      'pause_count': metadata.pauseCount,
      'interruption_count': metadata.interruptionCount,
      'mean_confidence': metadata.meanConfidence,
      if (metadata.affectConfirmed) 'affect': metadata.affect!.name,
      'affect_confirmed': metadata.affectConfirmed,
    };
  }

  void clear() => _records.clear();

  void _requireAvailable() {
    if (_safeModeReader()) {
      throw StateError('Voice metadata is unavailable in Safe Mode.');
    }
  }
}

void _requireId(String value, String name) {
  if (value.isEmpty ||
      value.length > 128 ||
      value.trim() != value ||
      value.codeUnits.any((unit) => unit < 0x21 || unit == 0x7f)) {
    throw FormatException('Invalid voice metadata $name.');
  }
}
