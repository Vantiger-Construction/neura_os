import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/journal_entry.dart';
import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';
import 'auth_service.dart';
import 'conflict_resolution_service.dart';
import 'sync_conflict_log.dart';

@visibleForTesting
bool shouldAttemptCloudSync({
  required bool configured,
  required bool safeMode,
  required bool clientAvailable,
}) =>
    configured && !safeMode && clientAvailable;

class SyncService {
  static const _kLocalKey = 'journal_entries';
  static const _kTable = 'journal_entries';

  SupabaseClient get _supabase => Supabase.instance.client;
  final _conflict = ConflictResolutionService();

  /// Pushes local journal entries and merges remote changes when cloud sync
  /// is configured, initialized, signed in, and allowed by the current mode.
  Future<void> syncAll() async {
    if (!shouldAttemptCloudSync(
      configured: SupabaseConfig.isConfigured,
      safeMode: SafeBoot.instance.safeMode.value,
      clientAvailable: AuthService.isAvailable,
    )) {
      return;
    }

    try {
      final statuses = await Connectivity().checkConnectivity();
      if (statuses.every((status) => status == ConnectivityResult.none)) {
        return;
      }

      // Keep every Supabase access inside the guarded block. A configured
      // project can still be intentionally uninitialized in Safe Mode or
      // temporarily unavailable after a failed optional cloud startup.
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _pushLocal(userId);
      await _pullRemote(userId);
    } catch (error, stack) {
      await AppLog.instance.caught('sync_failed', error, stack);
    }
  }

  Future<void> _pushLocal(String userId) async {
    final local = await _loadLocal();
    if (local.isEmpty) return;

    final rows = local
        .map(
          (entry) => {
            ...entry.toMap(),
            'user_id': userId,
          },
        )
        .toList();

    await _supabase.from(_kTable).upsert(rows, onConflict: 'id');
  }

  Future<void> _pullRemote(String userId) async {
    final response = await _supabase
        .from(_kTable)
        .select()
        .eq('user_id', userId)
        .order('timestamp', ascending: false);

    final remote = (response as List)
        .map(
          (row) => JournalEntry.fromMap(row as Map<String, dynamic>),
        )
        .toList();

    if (remote.isEmpty) return;

    final local = await _loadLocal();
    final merged = await mergeEntries(local, remote);
    await _saveLocal(merged);
  }

  /// Merges local and remote revisions, resolving conflicts by revision
  /// time. Every resolution with genuinely divergent content is recorded in
  /// [SyncConflictLog] (id, timestamps, winner only -- never the content
  /// itself), so an automatic merge is never silent.
  @visibleForTesting
  Future<List<JournalEntry>> mergeEntries(
    List<JournalEntry> local,
    List<JournalEntry> remote,
  ) async {
    final map = <String, JournalEntry>{};
    for (final entry in local) {
      map[entry.id] = entry;
    }
    for (final entry in remote) {
      final existing = map[entry.id];
      if (existing == null) {
        map[entry.id] = entry;
        continue;
      }
      final decision = _conflict.decide(existing, entry);
      map[entry.id] = decision.entry;
      if (decision.hadDivergentContent) {
        await SyncConflictLog.instance.record(
          SyncConflictRecord(
            entryId: entry.id,
            resolvedAt: DateTime.now(),
            localUpdatedAt: existing.effectiveUpdatedAt,
            remoteUpdatedAt: entry.effectiveUpdatedAt,
            winner: decision.winner,
          ),
        );
      }
    }
    return map.values.toList()
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
  }

  Future<List<JournalEntry>> _loadLocal() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getStringList(_kLocalKey) ?? [];
    return raw
        .map(
          (encoded) => JournalEntry.fromMap(
            jsonDecode(encoded) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> _saveLocal(List<JournalEntry> entries) async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setStringList(
      _kLocalKey,
      entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }
}
