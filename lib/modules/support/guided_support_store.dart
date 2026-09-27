import 'dart:convert';

import '../../core/memory/memory_crypto.dart';
import '../../reliability/safe_boot.dart';
import '../../startup/neura_prefs_cache.dart';
import 'guided_support_activity.dart';

class RememberedSupportActivity {
  const RememberedSupportActivity(this.activity, this.confirmedAtUtc);

  final GuidedSupportActivity activity;
  final DateTime confirmedAtUtc;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'activity': activity.name,
        'confirmedAtUtc': confirmedAtUtc.toIso8601String(),
        'scope': 'suggest_in_guided_support',
      };

  String exportText() => const JsonEncoder.withIndent('  ').convert(toJson());

  static RememberedSupportActivity fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['scope'] != 'suggest_in_guided_support') {
      throw const FormatException('Unknown guided support preference.');
    }
    final activity =
        GuidedSupportActivity.values.byName(json['activity'] as String);
    final date = DateTime.parse(json['confirmedAtUtc'] as String);
    if (!date.isUtc) {
      throw const FormatException('Invalid preference confirmation time.');
    }
    return RememberedSupportActivity(activity, date);
  }
}

/// One explicitly confirmed activity preference, encrypted locally using the
/// existing device key. Never accepts writing, check-in history or transcripts.
/// This preference is used only by the guided support screen, never AI context.
class GuidedSupportStore {
  GuidedSupportStore({Future<MemoryCrypto> Function()? loadCrypto})
      : _loadCrypto = loadCrypto ?? MemoryCrypto.demo;

  static final instance = GuidedSupportStore();
  static const storageKey = 'neura.guidedSupport.preference.v1';
  final Future<MemoryCrypto> Function() _loadCrypto;
  Future<void> _queue = Future<void>.value();
  int _generation = 0;
  bool _suspended = false;

  bool _allowed(int generation) =>
      !_suspended &&
      generation == _generation &&
      !SafeBoot.instance.safeMode.value;

  Future<RememberedSupportActivity?> read() async {
    final generation = _generation;
    if (!_allowed(generation)) return null;
    await _queue;
    if (!_allowed(generation)) return null;
    final raw = NeuraPrefsCache.prefs.getString(storageKey);
    if (raw == null) return null;
    final crypto = await _loadCrypto();
    if (!_allowed(generation)) return null;
    final json = await crypto.decryptJson(raw);
    if (!_allowed(generation)) return null;
    // Corrupt or unavailable data is surfaced; never reinterpret as plaintext.
    return RememberedSupportActivity.fromJson(json);
  }

  Future<RememberedSupportActivity> rememberAfterConfirmation(
    GuidedSupportActivity activity, {
    required bool Function() stillApproved,
  }) {
    final generation = _generation;
    void requireApproval() {
      if (!_allowed(generation) || !stillApproved()) {
        throw StateError('Support preference approval is no longer active.');
      }
    }

    return _enqueue(() async {
      requireApproval();
      final record =
          RememberedSupportActivity(activity, DateTime.now().toUtc());
      final crypto = await _loadCrypto();
      requireApproval();
      final blob = await crypto.encryptJson(record.toJson());
      requireApproval();
      final prefs = NeuraPrefsCache.prefs;
      final written = await prefs.setString(storageKey, blob);
      if (!written || !_allowed(generation) || !stillApproved()) {
        await prefs.remove(storageKey);
        throw StateError('Support preference save did not complete.');
      }
      return record;
    });
  }

  /// Forgetting revokes queued approvals immediately, including during recovery.
  Future<void> forget() {
    _generation++;
    return _enqueue(() async {
      final prefs = NeuraPrefsCache.prefs;
      if (!await prefs.remove(storageKey) || prefs.containsKey(storageKey)) {
        throw StateError('Support preference deletion could not be verified.');
      }
    });
  }

  Future<void> resetAfterDataWipe() async {
    _suspended = true;
    _generation++;
    await _queue.timeout(const Duration(seconds: 3));
    await forget();
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
