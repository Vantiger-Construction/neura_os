import 'dart:convert';

import '../models/contact_share_record.dart';
import '../../startup/neura_prefs_cache.dart';

/// Local, bounded history of mood-trend shares with trusted contacts.
///
/// This service never sees mood scores or notes -- it only records that a
/// share happened, for which contact, covering which date range, and how
/// many entries it contained. The actual summary text is generated and
/// handed to the OS share sheet by the caller and is never persisted here.
class ContactShareService {
  ContactShareService._internal();
  static final ContactShareService instance = ContactShareService._internal();

  static const _keyShares = 'care_contact_shares_v1';

  List<ContactShareRecord> _shares = [];
  bool _loaded = false;

  List<ContactShareRecord> get shares => List.unmodifiable(_shares);

  List<ContactShareRecord> sharesForContact(String contactId) {
    final matches = _shares.where((s) => s.contactId == contactId).toList()
      ..sort((a, b) => b.sharedAt.compareTo(a.sharedAt));
    return List.unmodifiable(matches);
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_keyShares);
    if (raw == null) {
      _shares = [];
      _loaded = true;
      return;
    }
    try {
      final list = json.decode(raw);
      if (list is List) {
        _shares = list
            .whereType<Map<String, dynamic>>()
            .map(
              (m) => ContactShareRecord.fromMap(Map<String, dynamic>.from(m)),
            )
            .toList();
      } else {
        _shares = [];
      }
    } catch (_) {
      // Self-heal: corrupted JSON -> clear storage and start fresh.
      _shares = [];
      await prefs.remove(_keyShares);
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = NeuraPrefsCache.prefs;
    final list = _shares.map((s) => s.toMap()).toList();
    await prefs.setString(_keyShares, json.encode(list));
  }

  Future<ContactShareRecord> recordShare({
    required String contactId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required int entryCount,
  }) async {
    await load();
    final now = DateTime.now();
    var idMicros = now.microsecondsSinceEpoch;
    while (_shares.any((share) => share.id == 'share_$idMicros')) {
      idMicros++;
    }
    final record = ContactShareRecord(
      id: 'share_$idMicros',
      contactId: contactId,
      sharedAt: now,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      entryCount: entryCount,
    );
    _shares.insert(0, record);
    await _save();
    return record;
  }

  /// Removes [id] from this device's local share history.
  ///
  /// This is bookkeeping only: once a summary has left the device through
  /// the OS share sheet, Neura has no way to recall it. This only forgets
  /// that the share happened, so the "Shared history" list stays accurate.
  Future<void> removeFromHistory(String id) async {
    await load();
    _shares.removeWhere((s) => s.id == id);
    await _save();
  }

  Future<void> clearForContact(String contactId) async {
    await load();
    _shares.removeWhere((s) => s.contactId == contactId);
    await _save();
  }

  void resetAfterDataWipe() {
    _shares = [];
    _loaded = false;
  }
}
