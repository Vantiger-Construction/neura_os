import 'dart:convert';
import 'models/trusted_contact.dart';
import '../../../startup/neura_prefs_cache.dart';

class LegacyTrustedContactsService {
  LegacyTrustedContactsService._();

  static final LegacyTrustedContactsService instance =
      LegacyTrustedContactsService._();

  static const String _kKey = 'neura_legacy_trusted_contacts_v1';

  Future<List<TrustedContact>> listContacts() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => TrustedContact.fromMap(m.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveContacts(List<TrustedContact> contacts) async {
    final prefs = NeuraPrefsCache.prefs;
    final list = contacts.map((c) => c.toMap()).toList();
    await prefs.setString(_kKey, jsonEncode(list));
  }

  Future<TrustedContact> upsert(TrustedContact contact) async {
    final existing = await listContacts();
    final idx = existing.indexWhere((c) => c.id == contact.id);
    final now = DateTime.now();

    final updated = contact.copyWith(updatedAt: now);
    final out = [...existing];
    if (idx >= 0) {
      out[idx] = updated;
    } else {
      out.add(updated.copyWith(createdAt: now));
    }
    await saveContacts(out);
    return updated;
  }

  Future<void> deleteById(String id) async {
    final existing = await listContacts();
    final out = existing.where((c) => c.id != id).toList();
    await saveContacts(out);
  }
}
