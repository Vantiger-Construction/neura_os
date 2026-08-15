import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../modules/quests/quest_models.dart';
import '../modules/quests/quest_store.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';
import 'approval_broker.dart';
import 'capability_registry.dart';
import 'models.dart';

/// Runtime binding for capability executors that Neura is currently allowed
/// to offer. The broker remains the final authority for every side effect.
///
/// Consent and action status are persisted as bounded metadata only. Candidate
/// copy and raw goal text stay out of the audit ledger.
class NeuraActionLoom {
  NeuraActionLoom._() {
    final questExecutor = _QuestPlanExecutor();
    _questExecutor = questExecutor;
    broker = NeuraApprovalBroker(
      executors: {
        NeuraCapabilityRegistry.changeLocalPlan: questExecutor,
      },
      safeModeReader: () => SafeBoot.instance.safeMode.value,
    );
  }

  static final NeuraActionLoom instance = NeuraActionLoom._();

  static const _ledgerKey = 'neura.action_loom.ledger.v1';
  static const _maxLedgerEntries = 100;

  late final NeuraApprovalBroker broker;
  late final _QuestPlanExecutor _questExecutor;
  Future<void> _ledgerQueue = Future<void>.value();
  bool _suspended = false;
  int _dataGeneration = 0;

  Future<NeuraApprovalAction> submit(NeuraCouncilDecision decision) async {
    final generation = _beginOperation();
    final action = await broker.submit(decision);
    _ensureCurrent(generation);
    await _persistMetadata(action, generation);
    return action;
  }

  Future<NeuraApprovalAction> approve(String actionId) async {
    final generation = _beginOperation();
    final action = broker.approve(actionId);
    _ensureCurrent(generation);
    await _persistMetadata(action, generation);
    return action;
  }

  Future<NeuraApprovalAction> deny(String actionId) async {
    final generation = _beginOperation();
    final action = broker.deny(actionId);
    _ensureCurrent(generation);
    await _persistMetadata(action, generation);
    return action;
  }

  Future<NeuraApprovalAction> execute(String actionId) async {
    final generation = _beginOperation();
    final action = await broker.execute(actionId);
    _ensureCurrent(generation);
    await _persistMetadata(action, generation);
    return action;
  }

  Future<NeuraApprovalAction> undo(String actionId) async {
    final generation = _beginOperation();
    final action = await broker.undo(actionId);
    _ensureCurrent(generation);
    await _persistMetadata(action, generation);
    return action;
  }

  Future<void> _persistMetadata(
    NeuraApprovalAction action,
    int generation,
  ) {
    _ensureCurrent(generation);
    final next = _ledgerQueue.then(
      (_) => _isCurrent(generation)
          ? _writeMetadata(action)
          : Future<void>.value(),
      onError: (_) => _isCurrent(generation)
          ? _writeMetadata(action)
          : Future<void>.value(),
    );
    _ledgerQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// Revokes process-local proposals and drains writes before backing stores
  /// are removed. A failed wipe deliberately leaves the loom suspended.
  Future<void> resetAfterDataWipe() async {
    _suspended = true;
    _dataGeneration += 1;
    final ledgerDrain = _ledgerQueue;
    try {
      await Future.wait<void>([
        broker.resetAfterDataWipe(),
        _questExecutor.resetAfterDataWipe(),
        ledgerDrain,
      ]).timeout(const Duration(seconds: 3));
      await NeuraPrefsCache.prefs.remove(_ledgerKey);
    } catch (_) {
      unawaited(
        ledgerDrain.then<void>(
          (_) async {
            await NeuraPrefsCache.prefs.remove(_ledgerKey);
          },
          onError: (_, __) async {
            await NeuraPrefsCache.prefs.remove(_ledgerKey);
          },
        ).catchError((_) {}),
      );
      rethrow;
    } finally {
      _ledgerQueue = Future<void>.value();
    }
  }

  void resumeAfterDataWipe() {
    broker.resumeAfterDataWipe();
    _questExecutor.resumeAfterDataWipe();
    _ledgerQueue = Future<void>.value();
    _suspended = false;
  }

  /// Simulates a process restart without touching durable execution records.
  @visibleForTesting
  Future<void> resetApprovalCacheForTesting() async {
    _suspended = true;
    _dataGeneration += 1;
    await _ledgerQueue;
    await broker.resetAfterDataWipe();
    broker.resumeAfterDataWipe();
    _ledgerQueue = Future<void>.value();
    _suspended = false;
  }

  int _beginOperation() {
    if (_suspended) {
      throw StateError('Action Loom is suspended after a data wipe.');
    }
    return _dataGeneration;
  }

  bool _isCurrent(int generation) =>
      !_suspended && generation == _dataGeneration;

  void _ensureCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw StateError('The action was revoked by a local-data wipe.');
    }
  }

  Future<void> _writeMetadata(NeuraApprovalAction action) async {
    final prefs = NeuraPrefsCache.prefs;
    final records = _decodeRecordList(prefs.getString(_ledgerKey));
    records.removeWhere((item) => item['action_id'] == action.id);
    records.add({
      'v': 1,
      'action_id': action.id,
      'candidate_id': action.candidate.id,
      'receipt_id': action.receipt.id,
      'capability_id': action.capability.id,
      'status': action.status.name,
      'explicit_user_approval': action.explicitUserApproval,
      'submitted_at': action.submittedAt.toUtc().toIso8601String(),
      'reviewed_at': action.reviewedAt?.toUtc().toIso8601String(),
      'executed_at': action.executedAt?.toUtc().toIso8601String(),
      'undone_at': action.undoneAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    records.sort(
      (left, right) => (left['updated_at']?.toString() ?? '')
          .compareTo(right['updated_at']?.toString() ?? ''),
    );
    if (records.length > _maxLedgerEntries) {
      records.removeRange(0, records.length - _maxLedgerEntries);
    }
    final written = await prefs.setString(_ledgerKey, jsonEncode(records));
    if (!written) {
      throw StateError('The local action audit ledger could not be updated.');
    }
  }
}

class _QuestPlanExecutor implements NeuraCapabilityExecutor {
  static const _executionKey = 'neura.action_loom.quest_executions.v1';
  static const _maxExecutionEntries = 100;

  Future<void> _queue = Future<void>.value();
  bool _suspended = false;
  int _dataGeneration = 0;

  @override
  Future<NeuraCapabilityExecutionResult> execute(
    NeuraCapabilityInvocation invocation,
  ) {
    final generation = _beginOperation();
    return _serialise(() => _execute(invocation, generation));
  }

  Future<NeuraCapabilityExecutionResult> _execute(
    NeuraCapabilityInvocation invocation,
    int generation,
  ) async {
    _ensureCurrent(generation);
    final payload = invocation.candidate.payload;
    if (payload['action'] != 'draft_quest') {
      throw UnsupportedError('Unsupported local-plan action.');
    }
    final goal = payload['goal']?.toString().trim() ?? '';
    if (goal.isEmpty) throw const FormatException('The goal is missing.');

    final fingerprint = await _fingerprint(invocation.candidate);
    final records = _loadExecutionRecords();
    final existing = records[invocation.candidate.id];
    if (existing != null) {
      _assertFingerprint(existing, fingerprint);
      final status = existing['status']?.toString();
      final questId = existing['quest_id']?.toString() ?? '';
      if (status == 'undone') {
        throw StateError('This exact approved action was already undone.');
      }
      if (questId.isEmpty) {
        throw StateError('The durable quest execution record is incomplete.');
      }
      final quests = await QuestStore.instance.getQuests();
      _ensureCurrent(generation);
      final questExists = quests.any((quest) => quest.id == questId);
      if (status == 'executed') {
        if (!questExists) {
          throw StateError(
            'The previously created quest was removed; refusing to recreate '
            'it without a new proposal.',
          );
        }
        return NeuraCapabilityExecutionResult(
          value: questId,
          undoToken: questId,
        );
      }
      if (status != 'executing') {
        throw StateError('Unknown durable quest execution status.');
      }
      if (!questExists) {
        await _addQuest(
          questId: questId,
          goal: goal,
          generation: generation,
        );
      }
      await _writeExecutionRecord(
        records,
        candidateId: invocation.candidate.id,
        fingerprint: fingerprint,
        questId: questId,
        status: 'executed',
        generation: generation,
      );
      return NeuraCapabilityExecutionResult(
        value: questId,
        undoToken: questId,
      );
    }

    final questId = 'nq_${fingerprint.substring(0, 24)}';
    await _writeExecutionRecord(
      records,
      candidateId: invocation.candidate.id,
      fingerprint: fingerprint,
      questId: questId,
      status: 'executing',
      generation: generation,
    );
    var questCreated = false;
    try {
      await _addQuest(
        questId: questId,
        goal: goal,
        generation: generation,
      );
      questCreated = true;
      await _writeExecutionRecord(
        records,
        candidateId: invocation.candidate.id,
        fingerprint: fingerprint,
        questId: questId,
        status: 'executed',
        generation: generation,
      );
    } catch (_) {
      if (questCreated) {
        if (_isCurrent(generation)) {
          await QuestStore.instance.deleteQuest(questId);
        } else {
          await _purgeAfterDataWipe();
        }
      }
      rethrow;
    }
    return NeuraCapabilityExecutionResult(
      value: questId,
      undoToken: questId,
    );
  }

  @override
  Future<void> undo(
    NeuraCapabilityInvocation invocation,
    NeuraCapabilityExecutionResult result,
  ) {
    final generation = _beginOperation();
    return _serialise(() => _undo(invocation, result, generation));
  }

  Future<void> _undo(
    NeuraCapabilityInvocation invocation,
    NeuraCapabilityExecutionResult result,
    int generation,
  ) async {
    _ensureCurrent(generation);
    final questId = result.undoToken;
    if (questId is! String || questId.isEmpty) {
      throw StateError('The quest undo token is missing.');
    }
    final fingerprint = await _fingerprint(invocation.candidate);
    final records = _loadExecutionRecords();
    final existing = records[invocation.candidate.id];
    if (existing == null) {
      throw StateError('The durable quest execution record is missing.');
    }
    _assertFingerprint(existing, fingerprint);
    if (existing['quest_id'] != questId) {
      throw StateError('The quest undo token does not match the action.');
    }
    if (existing['status'] == 'undone') return;

    final done = await QuestStore.instance.getDone();
    _ensureCurrent(generation);
    if (done.any((item) => item.questId == questId)) {
      throw const NeuraUndoUnavailableException(
        'Undo is unavailable after progress has been recorded for this quest.',
      );
    }

    await _writeExecutionRecord(
      records,
      candidateId: invocation.candidate.id,
      fingerprint: fingerprint,
      questId: questId,
      status: 'undoing',
      generation: generation,
    );
    await QuestStore.instance.deleteQuest(questId);
    _ensureCurrent(generation);
    await _writeExecutionRecord(
      records,
      candidateId: invocation.candidate.id,
      fingerprint: fingerprint,
      questId: questId,
      status: 'undone',
      generation: generation,
    );
  }

  Future<void> _addQuest({
    required String questId,
    required String goal,
    required int generation,
  }) async {
    _ensureCurrent(generation);
    final quests = await QuestStore.instance.getQuests();
    _ensureCurrent(generation);
    if (quests.any((quest) => quest.id == questId)) return;
    final safeGoal = goal.length > 80 ? '${goal.substring(0, 77)}...' : goal;
    await QuestStore.instance.add(
      Quest(
        id: questId,
        title: 'Take one step toward "$safeGoal"',
        details: 'Make it tiny: 5–15 minutes. Done beats perfect.',
        createdAt: DateTime.now(),
      ),
    );
    if (!_isCurrent(generation)) {
      await _purgeAfterDataWipe();
      _ensureCurrent(generation);
    }
  }

  Map<String, Map<String, Object?>> _loadExecutionRecords() {
    final raw = NeuraPrefsCache.prefs.getString(_executionKey);
    if (raw == null || raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid durable quest execution ledger.');
    }
    final records = <String, Map<String, Object?>>{};
    for (final item in decoded) {
      if (item is! Map) {
        throw const FormatException('Invalid quest execution entry.');
      }
      final record = Map<String, Object?>.from(item);
      final candidateId = record['candidate_id']?.toString() ?? '';
      if (candidateId.isEmpty) {
        throw const FormatException('Quest execution candidate id is missing.');
      }
      records[candidateId] = record;
    }
    return records;
  }

  Future<void> _writeExecutionRecord(
    Map<String, Map<String, Object?>> records, {
    required String candidateId,
    required String fingerprint,
    required String questId,
    required String status,
    required int generation,
  }) async {
    _ensureCurrent(generation);
    records[candidateId] = {
      'v': 1,
      'candidate_id': candidateId,
      'payload_fingerprint': fingerprint,
      'quest_id': questId,
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final ordered = records.values.toList(growable: true)
      ..sort(
        (left, right) => (left['updated_at']?.toString() ?? '')
            .compareTo(right['updated_at']?.toString() ?? ''),
      );
    if (ordered.length > _maxExecutionEntries) {
      ordered.removeRange(0, ordered.length - _maxExecutionEntries);
    }
    final written = await NeuraPrefsCache.prefs.setString(
      _executionKey,
      jsonEncode(ordered),
    );
    if (!written) {
      throw StateError('The durable quest execution ledger could not be saved.');
    }
    if (!_isCurrent(generation)) {
      await NeuraPrefsCache.prefs.remove(_executionKey);
      _ensureCurrent(generation);
    }
  }

  Future<void> resetAfterDataWipe() async {
    _suspended = true;
    _dataGeneration += 1;
    try {
      await _queue.timeout(const Duration(seconds: 3));
      await _purgeAfterDataWipe();
    } on TimeoutException {
      unawaited(
        _queue.then<void>(
          (_) => _purgeAfterDataWipe(),
          onError: (_, __) => _purgeAfterDataWipe(),
        ).catchError((_) {}),
      );
      rethrow;
    }
  }

  void resumeAfterDataWipe() {
    _queue = Future<void>.value();
    _suspended = false;
  }

  int _beginOperation() {
    if (_suspended) {
      throw StateError('Quest actions are suspended after a data wipe.');
    }
    return _dataGeneration;
  }

  bool _isCurrent(int generation) =>
      !_suspended && generation == _dataGeneration;

  void _ensureCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw StateError('The quest action was revoked by a local-data wipe.');
    }
  }

  Future<void> _purgeAfterDataWipe() async {
    await QuestStore.instance.wipe();
    await NeuraPrefsCache.prefs.remove(_executionKey);
  }

  void _assertFingerprint(
    Map<String, Object?> record,
    String fingerprint,
  ) {
    if (record['payload_fingerprint'] != fingerprint) {
      throw StateError(
        'Candidate id was reused with a different local-plan payload.',
      );
    }
  }

  Future<String> _fingerprint(NeuraIntelligenceCandidate candidate) async {
    final canonical = jsonEncode(
      _canonicalValue({
        'candidate_id': candidate.id,
        'capability_id': candidate.capabilityId,
        'payload': candidate.payload,
      }),
    );
    final hash = await Sha256().hash(utf8.encode(canonical));
    return base64UrlEncode(hash.bytes).replaceAll('=', '');
  }

  Object? _canonicalValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {
        for (final key in keys) key: _canonicalValue(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalValue).toList(growable: false);
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw FormatException(
      'Unsupported value in capability payload: ${value.runtimeType}.',
    );
  }

  Future<T> _serialise<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

List<Map<String, Object?>> _decodeRecordList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw const FormatException('Invalid local action audit ledger.');
  }
  return decoded.map((item) {
    if (item is! Map) {
      throw const FormatException('Invalid local action audit entry.');
    }
    return Map<String, Object?>.from(item);
  }).toList(growable: true);
}
