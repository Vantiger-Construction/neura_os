import 'dart:async';

import 'money_models.dart';
import '../../core/memory/memory_crypto.dart';
import '../../startup/neura_prefs_cache.dart';

/// Local, encrypted-at-rest income/expense history. Same shape as
/// MoodStore: a single encrypted blob (not JSONL) since the whole list
/// needs to be read anyway to compute a running balance.
class MoneyStore {
  MoneyStore._();
  static final MoneyStore instance = MoneyStore._();

  static const _key = 'neura.money.entries.v1';

  MemoryCrypto? _crypto;
  Future<void> _writeQueue = Future<void>.value();
  bool _writesSuspended = false;
  int _dataGeneration = 0;

  Future<MemoryCrypto> _ensureCrypto() async {
    _crypto ??= await MemoryCrypto.demo();
    return _crypto!;
  }

  Future<List<MoneyEntry>> getAll() async {
    if (_writesSuspended) return <MoneyEntry>[];
    return _readAll(_dataGeneration);
  }

  Future<List<MoneyEntry>> _readAll(int generation) async {
    if (!_isCurrent(generation)) return <MoneyEntry>[];
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key) ?? '';
    if (raw.trim().isEmpty) return <MoneyEntry>[];

    final crypto = await _ensureCrypto();
    if (!_isCurrent(generation)) return <MoneyEntry>[];
    try {
      final decrypted = await crypto.decryptJson(raw);
      if (!_isCurrent(generation)) return <MoneyEntry>[];
      final items = (decrypted['items'] as List)
          .whereType<Map>()
          .map((m) => MoneyEntry.fromJson(Map<String, Object?>.from(m)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return items;
    } catch (_) {
      // Not a valid encrypted blob - either corrupt, or first run.
      return <MoneyEntry>[];
    }
  }

  Future<void> add(MoneyEntry entry) {
    return _enqueueWrite((generation) async {
      final items = await _readAll(generation);
      _requireCurrent(generation);
      items.add(entry);
      await _persist(items, generation);
    });
  }

  Future<void> remove(String id) {
    return _enqueueWrite((generation) async {
      final items = await _readAll(generation);
      _requireCurrent(generation);
      items.removeWhere((e) => e.id == id);
      await _persist(items, generation);
    });
  }

  Future<void> _persist(List<MoneyEntry> items, int generation) async {
    _requireCurrent(generation);
    final crypto = await _ensureCrypto();
    _requireCurrent(generation);
    final blob = await crypto.encryptJson({
      'items': items.map((e) => e.toJson()).toList(),
    });
    _requireCurrent(generation);
    await NeuraPrefsCache.prefs.setString(_key, blob);
    if (!_isCurrent(generation)) {
      await NeuraPrefsCache.prefs.remove(_key);
      _requireCurrent(generation);
    }
  }

  Future<double> balance() async {
    final items = await getAll();
    return items.fold<double>(0, (sum, e) => sum + e.signedAmount);
  }

  /// Totals for the current calendar month.
  Future<({double income, double expense})> thisMonthSummary() async {
    final items = await getAll();
    final now = DateTime.now();
    final thisMonth = items.where(
        (e) => e.timestamp.year == now.year && e.timestamp.month == now.month);
    var income = 0.0;
    var expense = 0.0;
    for (final e in thisMonth) {
      if (e.type == MoneyEntryType.income) {
        income += e.amount;
      } else {
        expense += e.amount;
      }
    }
    return (income: income, expense: expense);
  }

  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    Object? drainFailure;
    try {
      await _writeQueue.timeout(const Duration(seconds: 3));
    } catch (error) {
      drainFailure = error;
    }
    _crypto = null;
    _writeQueue = Future<void>.value();
    if (drainFailure != null) {
      throw StateError('Money history writer shutdown could not be verified.');
    }
  }

  Future<T> _enqueueWrite<T>(
    Future<T> Function(int generation) operation,
  ) {
    if (_writesSuspended) {
      return Future<T>.error(StateError('Money history writes are suspended.'));
    }
    final generation = _dataGeneration;
    Future<T> run() {
      _requireCurrent(generation);
      return operation(generation);
    }

    final next = _writeQueue.then<T>(
      (_) => run(),
      onError: (_) => run(),
    );
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;

  void _requireCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw StateError('Money history operation was invalidated.');
    }
  }
}
