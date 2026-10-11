import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/journal_entry.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';
import 'auth_service.dart';
import 'conflict_resolution_service.dart';
import 'local_journal_store.dart';
import 'sync_conflict_log.dart';
import 'sync_recovery.dart';

export 'sync_recovery.dart';

@visibleForTesting
bool shouldAttemptCloudSync({
  required bool configured,
  required bool safeMode,
  required bool clientAvailable,
}) =>
    configured && !safeMode && clientAvailable;

class SyncService {
  SyncService()
      : _testLoad = null,
        _testSave = null,
        _testFetch = null,
        _testPush = null,
        _testAllowed = null,
        _testUser = null,
        _testOnline = null;

  @visibleForTesting
  SyncService.forTesting({
    required Future<List<JournalEntry>> Function() loadLocal,
    required Future<void> Function(List<JournalEntry>) saveLocal,
    required Future<List<JournalEntry>> Function(String, int, int) fetchPage,
    required Future<JournalEntry> Function(JournalEntry, DateTime?)
        pushRevision,
    required bool Function() allowed,
    required String? Function() userId,
    required Future<bool> Function() online,
  })  : _testLoad = loadLocal,
        _testSave = saveLocal,
        _testFetch = fetchPage,
        _testPush = pushRevision,
        _testAllowed = allowed,
        _testUser = userId,
        _testOnline = online;

  final Future<List<JournalEntry>> Function()? _testLoad;
  final Future<void> Function(List<JournalEntry>)? _testSave;
  final Future<List<JournalEntry>> Function(String, int, int)? _testFetch;
  final Future<JournalEntry> Function(JournalEntry, DateTime?)? _testPush;
  final bool Function()? _testAllowed;
  final String? Function()? _testUser;
  final Future<bool> Function()? _testOnline;

  String? get _currentUserId =>
      _testUser != null ? _testUser!() : _supabase.auth.currentUser?.id;

  static const _kTable = 'journal_entries';

  SupabaseClient get _supabase => Supabase.instance.client;
  final _localJournal = LocalJournalStore();
  final _conflict = ConflictResolutionService();

  static final _singleFlight = SyncSingleFlight();
  static const _lastResultKey = 'neura.sync.last_result.v1';

  static String? get lastResultMessage =>
      NeuraPrefsCache.prefsOrNull?.getString(_lastResultKey);

  Future<SyncResult> syncAll() => _singleFlight.run(_sync);

  bool get _allowed =>
      _testAllowed?.call() ??
      shouldAttemptCloudSync(
        configured: SupabaseConfig.isConfigured,
        safeMode: SafeBoot.instance.safeMode.value,
        clientAvailable: AuthService.isAvailable,
      );

  void _checkSession(String userId) {
    if (!_allowed || _currentUserId != userId) {
      throw const _SyncInterrupted();
    }
  }

  Future<SyncResult> _sync() async {
    final result = await _runSync();
    try {
      await NeuraPrefsCache.prefs.setString(_lastResultKey, result.message);
    } catch (_) {}
    return result;
  }

  Future<SyncResult> _runSync() async {
    SyncResult result;
    try {
      if (!_allowed) return const SyncResult(SyncOutcome.unavailable);
      final online = _testOnline != null
          ? await _testOnline!()
          : (await Connectivity().checkConnectivity())
              .any((status) => status != ConnectivityResult.none);
      if (!_allowed) return const SyncResult(SyncOutcome.unavailable);
      if (!online) {
        return const SyncResult(SyncOutcome.offline);
      }
      final userId = _currentUserId;
      if (userId == null) return const SyncResult(SyncOutcome.signedOut);
      // Pull before any push; pagination prevents dropping rows past the API cap.
      final remote = <JournalEntry>[];
      const pageSize = 500;
      for (var offset = 0;; offset += pageSize) {
        _checkSession(userId);
        if (offset >= 10000) throw StateError('Journal sync limit reached.');
        final rows = _testFetch != null
            ? await _testFetch!(userId, offset, pageSize)
            : (await _supabase
                    .from(_kTable)
                    .select()
                    .eq('user_id', userId)
                    .order('id')
                    .range(offset, offset + pageSize - 1))
                .map((row) => JournalEntry.fromMap(row))
                .toList();
        _checkSession(userId);
        remote.addAll(rows);
        if (rows.length < pageSize) break;
      }
      final planned = await _mergeRemoteSafely(userId, remote);
      final remoteById = {for (final entry in remote) entry.id: entry};
      final acknowledgements = <JournalEntry>[];
      final sent = <String, String>{};
      for (final entry in planned) {
        final cloud = remoteById[entry.id];
        if (cloud != null && _samePayload(entry, cloud)) continue;
        _checkSession(userId);
        // No legacy upsert fallback: deployments missing the RPC remain local.
        late final JournalEntry ack;
        if (_testPush != null) {
          ack = await _testPush!(entry, cloud?.effectiveUpdatedAt);
        } else {
          final response =
              await _supabase.rpc('neura_sync_journal_revision', params: {
            'entry': entry.toMap(),
            'expected_updated_at':
                cloud?.effectiveUpdatedAt.toUtc().toIso8601String(),
          });
          final rows = response as List;
          if (rows.length != 1) {
            throw StateError('Invalid sync acknowledgement.');
          }
          ack = JournalEntry.fromMap(
              Map<String, dynamic>.from(rows.single as Map));
        }
        _checkSession(userId);
        if (ack.id != entry.id) {
          throw StateError('Invalid sync acknowledgement.');
        }
        acknowledgements.add(ack);
        sent[entry.id] = _revision(entry);
      }
      // Server-assigned timestamps may acknowledge an older local upload.
      // Do not let that acknowledgement erase edits made during the request.
      await _mergeRemoteSafely(userId, acknowledgements, sent: sent);
      final current = await _loadLocal();
      _checkSession(userId);
      final known = {
        for (final entry in remote) entry.id: entry,
        for (final entry in acknowledgements) entry.id: entry
      };
      final pending = current
          .where((entry) =>
              known[entry.id] == null || !_samePayload(entry, known[entry.id]!))
          .length;
      result = SyncResult(
          pending == 0 ? SyncOutcome.complete : SyncOutcome.retryNeeded,
          pending: pending);
    } on _SyncInterrupted {
      result = const SyncResult(SyncOutcome.interrupted);
    } on PostgrestException catch (error) {
      result = SyncResult(error.code == 'PGRST202' || error.code == '42883'
          ? SyncOutcome.setupRequired
          : SyncOutcome.failed);
    } catch (_) {
      // Never put server response bodies or journal content in diagnostics.
      result = const SyncResult(SyncOutcome.failed);
    }
    return result;
  }

  Future<List<JournalEntry>> _mergeRemoteSafely(
      String userId, List<JournalEntry> remote,
      {Map<String, String>? sent}) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      _checkSession(userId);
      final local = await _loadLocal();
      final revisions = {for (final entry in local) entry.id: _revision(entry)};
      final eligible = sent == null
          ? remote
          : remote
              .where((entry) => mayApplySyncAcknowledgement(
                  currentRevision: revisions[entry.id],
                  sentRevision: sent[entry.id]!))
              .toList();
      final merged = await mergeEntries(local, eligible);
      _checkSession(userId);
      final latest = await _loadLocal();
      if (jsonEncode(latest.map((e) => e.toMap()).toList()) !=
          jsonEncode(local.map((e) => e.toMap()).toList())) {
        continue;
      }
      _checkSession(userId);
      await _saveLocal(merged);
      return merged;
    }
    throw StateError('Local journal changed while merging; retry safely.');
  }

  String _revision(JournalEntry entry) => jsonEncode(entry.toMap());
  bool _samePayload(JournalEntry a, JournalEntry b) =>
      a.content == b.content &&
      a.moodTag == b.moodTag &&
      a.isVoice == b.isVoice;

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
    if (_testLoad != null) return _testLoad!();
    return _localJournal.loadEntries();
  }

  Future<void> _saveLocal(List<JournalEntry> entries) async {
    if (_testSave != null) return _testSave!(entries);
    await _localJournal.saveEntries(entries);
  }
}

class _SyncInterrupted implements Exception {
  const _SyncInterrupted();
}
