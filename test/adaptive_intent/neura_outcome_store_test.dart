import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_plan_session.dart';
import 'package:neuro_companion/adaptive_intent/neura_outcome_store.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';

void main() {
  test('encrypted outcome store is bounded and restores derived metrics', () async {
    final backing = _MemoryBacking();
    final store = NeuraEncryptedOutcomeStore(
      cipher: const _Base64Cipher(),
      backing: backing,
      maxEntries: 3,
    );

    await store.save(
      List<NeuraPlanOutcomeReceipt>.generate(
        5,
        (index) => _outcome(index),
      ),
    );

    expect(backing.value, isNotNull);
    expect(backing.value, isNot(contains('session-4')));
    expect(backing.value, isNot(contains('private goal')));

    final restored = await store.load();
    expect(restored, hasLength(3));
    expect(restored.first.sessionId, 'session-2');
    expect(restored.last.sessionId, 'session-4');
    expect(restored.last.completionRatio, closeTo(0.8, 0.0001));
  });

  test('clear removes encrypted history', () async {
    final backing = _MemoryBacking();
    final store = NeuraEncryptedOutcomeStore(
      cipher: const _Base64Cipher(),
      backing: backing,
    );

    await store.save(<NeuraPlanOutcomeReceipt>[_outcome(0)]);
    expect(await store.load(), isNotEmpty);

    await store.clear();
    expect(backing.value, isNull);
    expect(await store.load(), isEmpty);
  });
}

NeuraPlanOutcomeReceipt _outcome(int index) {
  return NeuraPlanOutcomeReceipt(
    sessionId: 'session-$index',
    startedAt: DateTime.utc(2026, 8, 23, 8 + index),
    endedAt: DateTime.utc(2026, 8, 23, 9 + index),
    bandwidthMode: NeuraBandwidthMode.balanced,
    status: NeuraPlanSessionStatus.completed,
    totalLocalSteps: 5,
    completedLocalSteps: 4,
    deferredLocalSteps: 1,
    blockedSteps: 0,
    externalSteps: 0,
    completionRatio: 0.8,
    perceivedEffort: 0.5,
    satisfaction: 0.8,
    interruptionCount: index,
  );
}

class _MemoryBacking implements NeuraOutcomeBackingStore {
  String? value;

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async {
    value = next;
  }
}

class _Base64Cipher implements NeuraOutcomeCipher {
  const _Base64Cipher();

  @override
  Future<Map<String, dynamic>> decrypt(String value) async {
    return jsonDecode(
      utf8.decode(base64Decode(value)),
    ) as Map<String, dynamic>;
  }

  @override
  Future<String> encrypt(Map<String, dynamic> value) async {
    return base64Encode(utf8.encode(jsonEncode(value)));
  }
}
