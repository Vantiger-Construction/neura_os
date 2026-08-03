import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/journal_entry.dart';
import 'conflict_resolution_service.dart';
import '../startup/neura_prefs_cache.dart';

class SyncService {
  static const _kLocalKey = 'journal_entries';
  static const _kTable = 'journal_entries';

  // Lazy, not a field initializer: Supabase.instance.client throws if
  // Supabase.initialize() was never called, which is the case whenever
  // SupabaseConfig.isConfigured is false. Currently the only call site
  // (SyncStatusScreen) is UI-gated on isConfigured, but a field initializer
  // would crash the instant *anything* constructs SyncService() without
  // that gate — a getter keeps that danger from being reachable at all.
  SupabaseClient get _supabase => Supabase.instance.client;
  final _conflict = ConflictResolutionService();

  /// Starts sync when connectivity is available.
  /// Pushes local entries to Supabase and merges remote changes locally.
  Future<void> syncAll() async {
    if (!SupabaseConfig.isConfigured) return;

    final statuses = await Connectivity().checkConnectivity();
    if (statuses.every((s) => s == ConnectivityResult.none)) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return; // not signed in

    try {
      await _pushLocal(userId);
      await _pullRemote(userId);
    } catch (e) {
      debugPrint('SyncService: error during sync — $e');
    }
  }

  Future<void> _pushLocal(String userId) async {
    final local = await _loadLocal();
    if (local.isEmpty) return;

    final rows = local
        .map((e) => {
              ...e.toMap(),
              'user_id': userId,
            })
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
        .map((r) => JournalEntry.fromMap(r as Map<String, dynamic>))
        .toList();

    if (remote.isEmpty) return;

    final local = await _loadLocal();
    final merged = await _mergeEntries(local, remote);
    await _saveLocal(merged);
  }

  Future<List<JournalEntry>> _mergeEntries(
    List<JournalEntry> local,
    List<JournalEntry> remote,
  ) async {
    final map = <String, JournalEntry>{};
    for (final e in local) {
      map[e.id] = e;
    }
    for (final r in remote) {
      final existing = map[r.id];
      if (existing == null) {
        map[r.id] = r;
      } else {
        map[r.id] = await _conflict.resolve(existing, r);
      }
    }
    return map.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<List<JournalEntry>> _loadLocal() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getStringList(_kLocalKey) ?? [];
    return raw
        .map((s) => JournalEntry.fromMap(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveLocal(List<JournalEntry> entries) async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setStringList(
      _kLocalKey,
      entries.map((e) => jsonEncode(e.toMap())).toList(),
    );
  }
}
