import 'dart:convert';
import '../models/trusted_contact.dart';
import '../../startup/neura_prefs_cache.dart';

class TrustedContactsService {
  TrustedContactsService._internal();
  static final TrustedContactsService instance =
      TrustedContactsService._internal();

  static const _keyContacts = 'care_trusted_contacts_v1';

  List<TrustedContact> _contacts = [];
  bool _loaded = false;

  List<TrustedContact> get contacts => List.unmodifiable(_contacts);

  List<TrustedContact> get emergencyContacts =>
      _contacts.where((c) => c.isEmergency).toList(growable: false);

  List<TrustedContact> get professionalContacts =>
      _contacts.where((c) => c.isProfessional).toList(growable: false);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_keyContacts);
    if (raw == null) {
      _contacts = [];
      _loaded = true;
      return;
    }
    try {
      final list = json.decode(raw);
      if (list is List) {
        _contacts = list
            .whereType<Map<String, dynamic>>()
            .map((m) => TrustedContact.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      } else {
        _contacts = [];
      }
    } catch (e) {
      // Self-heal: corrupted JSON -> clear storage and start fresh.
      _contacts = [];
      await prefs.remove(_keyContacts);
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = NeuraPrefsCache.prefs;
    final list = _contacts.map((c) => c.toMap()).toList();
    await prefs.setString(_keyContacts, json.encode(list));
  }

  Future<void> addOrUpdate(TrustedContact contact) async {
    await load();
    final idx = _contacts.indexWhere((c) => c.id == contact.id);
    if (idx >= 0) {
      _contacts[idx] = contact;
    } else {
      _contacts.add(contact);
    }
    await _save();
  }

  Future<void> delete(String id) async {
    await load();
    _contacts.removeWhere((c) => c.id == id);
    await _save();
  }

  TrustedContact? findById(String id) {
    for (final c in _contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  void resetAfterDataWipe() {
    _contacts = [];
    _loaded = false;
  }
}
