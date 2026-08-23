import '../core/memory/memory_crypto.dart';
import '../startup/neura_prefs_cache.dart';
import '../cognitive/neura_cognitive_state.dart';
import 'neura_adaptive_plan_session.dart';

abstract interface class NeuraOutcomeCipher {
  Future<String> encrypt(Map<String, dynamic> value);

  Future<Map<String, dynamic>> decrypt(String value);
}

class NeuraMemoryOutcomeCipher implements NeuraOutcomeCipher {
  const NeuraMemoryOutcomeCipher();

  @override
  Future<String> encrypt(Map<String, dynamic> value) async {
    final crypto = await MemoryCrypto.demo();
    return crypto.encryptJson(value);
  }

  @override
  Future<Map<String, dynamic>> decrypt(String value) async {
    final crypto = await MemoryCrypto.demo();
    return crypto.decryptJson(value);
  }
}

abstract interface class NeuraOutcomeBackingStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> clear();
}

class NeuraPrefsOutcomeBackingStore implements NeuraOutcomeBackingStore {
  const NeuraPrefsOutcomeBackingStore();

  static const stateKey = 'neura.adaptive_intent.outcomes.v1';

  @override
  Future<String?> read() async {
    return NeuraPrefsCache.prefs.getString(stateKey);
  }

  @override
  Future<void> write(String value) async {
    final written = await NeuraPrefsCache.prefs.setString(stateKey, value);
    if (!written) {
      throw StateError('Adaptive Intent outcomes could not be saved.');
    }
  }

  @override
  Future<void> clear() async {
    await NeuraPrefsCache.prefs.remove(stateKey);
  }
}

abstract interface class NeuraOutcomeStore {
  Future<List<NeuraPlanOutcomeReceipt>> load();

  Future<void> save(Iterable<NeuraPlanOutcomeReceipt> outcomes);

  Future<void> clear();
}

class NeuraEncryptedOutcomeStore implements NeuraOutcomeStore {
  NeuraEncryptedOutcomeStore({
    NeuraOutcomeCipher cipher = const NeuraMemoryOutcomeCipher(),
    NeuraOutcomeBackingStore backing = const NeuraPrefsOutcomeBackingStore(),
    int maxEntries = 100,
  })  : _cipher = cipher,
        _backing = backing,
        _maxEntries = maxEntries.clamp(1, 500).toInt();

  final NeuraOutcomeCipher _cipher;
  final NeuraOutcomeBackingStore _backing;
  final int _maxEntries;

  @override
  Future<List<NeuraPlanOutcomeReceipt>> load() async {
    final encrypted = await _backing.read();
    if (encrypted == null || encrypted.trim().isEmpty) {
      return <NeuraPlanOutcomeReceipt>[];
    }

    final decoded = await _cipher.decrypt(encrypted);
    if (decoded['v'] != 1) {
      throw const FormatException(
        'Unsupported Adaptive Intent outcome-store version.',
      );
    }
    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'Adaptive Intent outcome history is malformed.',
      );
    }

    final outcomes = rawItems
        .whereType<Map>()
        .map(
          (item) => _outcomeFromJson(
            Map<String, Object?>.from(item),
          ),
        )
        .whereType<NeuraPlanOutcomeReceipt>()
        .toList(growable: true)
      ..sort((left, right) => left.endedAt.compareTo(right.endedAt));
    if (outcomes.length > _maxEntries) {
      outcomes.removeRange(0, outcomes.length - _maxEntries);
    }
    return outcomes;
  }

  @override
  Future<void> save(Iterable<NeuraPlanOutcomeReceipt> outcomes) async {
    final bounded = outcomes.toList(growable: true)
      ..sort((left, right) => left.endedAt.compareTo(right.endedAt));
    if (bounded.length > _maxEntries) {
      bounded.removeRange(0, bounded.length - _maxEntries);
    }

    final encrypted = await _cipher.encrypt(<String, dynamic>{
      'v': 1,
      'items': bounded.map((item) => item.toJson()).toList(growable: false),
    });
    await _backing.write(encrypted);
  }

  @override
  Future<void> clear() => _backing.clear();

  NeuraPlanOutcomeReceipt? _outcomeFromJson(
    Map<String, Object?> json,
  ) {
    final sessionId = json['session_id']?.toString().trim() ?? '';
    final startedAt = DateTime.tryParse(
      json['started_at']?.toString() ?? '',
    )?.toUtc();
    final endedAt = DateTime.tryParse(
      json['ended_at']?.toString() ?? '',
    )?.toUtc();
    if (sessionId.isEmpty || startedAt == null || endedAt == null) {
      return null;
    }

    return NeuraPlanOutcomeReceipt(
      sessionId: sessionId,
      startedAt: startedAt,
      endedAt: endedAt,
      bandwidthMode: _enumByName(
        NeuraBandwidthMode.values,
        json['bandwidth_mode'],
        NeuraBandwidthMode.recovery,
      ),
      status: _enumByName(
        NeuraPlanSessionStatus.values,
        json['status'],
        NeuraPlanSessionStatus.abandoned,
      ),
      totalLocalSteps: _boundedInt(json['total_local_steps'], 0, 0, 1000),
      completedLocalSteps:
          _boundedInt(json['completed_local_steps'], 0, 0, 1000),
      deferredLocalSteps: _boundedInt(json['deferred_local_steps'], 0, 0, 1000),
      blockedSteps: _boundedInt(json['blocked_steps'], 0, 0, 1000),
      externalSteps: _boundedInt(json['external_steps'], 0, 0, 1000),
      completionRatio: _unit(json['completion_ratio']),
      perceivedEffort: _unit(json['perceived_effort']),
      satisfaction: _unit(json['satisfaction']),
      interruptionCount: _boundedInt(json['interruption_count'], 0, 0, 100000),
    );
  }

  T _enumByName<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    final name = raw?.toString();
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  int _boundedInt(Object? raw, int fallback, int min, int max) {
    final value = raw is num ? raw.toInt() : fallback;
    return value.clamp(min, max).toInt();
  }

  double _unit(Object? raw) {
    return (raw is num ? raw.toDouble() : 0.0).clamp(0.0, 1.0).toDouble();
  }
}
