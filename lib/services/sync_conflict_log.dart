import 'dart:convert';

import '../startup/neura_prefs_cache.dart';
import 'conflict_resolution_service.dart';

/// Bounded, non-content record of one auto-resolved sync conflict.
///
/// Only identifiers, timestamps, and which side won are kept -- never the
/// journal content itself, so a silent merge stays visible without a new
/// copy of private text living outside the encrypted journal store.
class SyncConflictRecord {
  const SyncConflictRecord({
    required this.entryId,
    required this.resolvedAt,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.winner,
  });

  final String entryId;
  final DateTime resolvedAt;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;
  final ConflictWinner winner;

  Map<String, dynamic> toMap() => {
        'entryId': entryId,
        'resolvedAt': resolvedAt.toUtc().toIso8601String(),
        'localUpdatedAt': localUpdatedAt.toUtc().toIso8601String(),
        'remoteUpdatedAt': remoteUpdatedAt.toUtc().toIso8601String(),
        'winner': winner.name,
      };

  factory SyncConflictRecord.fromMap(Map<String, dynamic> map) {
    return SyncConflictRecord(
      entryId: map['entryId'] as String? ?? '',
      resolvedAt: _parseDate(map['resolvedAt']),
      localUpdatedAt: _parseDate(map['localUpdatedAt']),
      remoteUpdatedAt: _parseDate(map['remoteUpdatedAt']),
      winner: ConflictWinner.values.firstWhere(
        (value) => value.name == map['winner'],
        orElse: () => ConflictWinner.local,
      ),
    );
  }

  static DateTime _parseDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// Local, append-only log of resolved sync conflicts so an automatic merge
/// is never silent. Capped so it cannot grow without bound.
class SyncConflictLog {
  SyncConflictLog._internal();
  static final SyncConflictLog instance = SyncConflictLog._internal();

  static const _key = 'sync_conflict_log_v1';
  static const _maxRecords = 50;

  List<SyncConflictRecord> _records = [];
  bool _loaded = false;

  List<SyncConflictRecord> get records => List.unmodifiable(_records);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key);
    if (raw == null) {
      _records = [];
      _loaded = true;
      return;
    }
    try {
      final list = json.decode(raw);
      if (list is List) {
        _records = list
            .whereType<Map<String, dynamic>>()
            .map(
                (m) => SyncConflictRecord.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      } else {
        _records = [];
      }
    } catch (_) {
      // Self-heal: corrupted JSON -> clear storage and start fresh.
      _records = [];
      await prefs.remove(_key);
    }
    _loaded = true;
  }

  Future<void> record(SyncConflictRecord record) async {
    await load();
    _records.insert(0, record);
    if (_records.length > _maxRecords) {
      _records = _records.sublist(0, _maxRecords);
    }
    await _save();
  }

  Future<void> clear() async {
    _records = [];
    await NeuraPrefsCache.prefs.remove(_key);
  }

  Future<void> _save() async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(
      _key,
      json.encode(_records.map((r) => r.toMap()).toList()),
    );
  }

  void resetAfterDataWipe() {
    _records = [];
    _loaded = false;
  }
}
