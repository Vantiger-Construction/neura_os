import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/legacy_message_template.dart';
import '../../../startup/neura_prefs_cache.dart';

class LegacyTemplatesService {
  LegacyTemplatesService._();

  static final LegacyTemplatesService instance = LegacyTemplatesService._();

  static const String _kKey = 'neura_legacy_message_templates_v1';

  List<LegacyMessageTemplate> _defaults() {
    final now = DateTime.now();
    return [
      LegacyMessageTemplate(
        id: 'tpl_grandma',
        name: 'Send to Grandma',
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
        bodyTemplate:
            'Hi {contactName},\n\n'
            'This is a "Legacy Packet" from me, created in Neura Companion. '
            'It contains a message and any attachments I included.\n\n'
            'Packet name: "{capsuleTitle}"\n'
            'Date: {date}\n\n'
            'Love you. ❤️\n',
      ),
      LegacyMessageTemplate(
        id: 'tpl_instructions',
        name: 'Instructions (practical)',
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
        bodyTemplate:
            'Hello {contactName},\n\n'
            'I\'m sharing a Legacy Packet titled "{capsuleTitle}". '
            'It was generated on {date}.\n\n'
            'Open the ZIP and read the README first. '
            'If anything is encrypted, you\'ll need the passphrase I gave you separately.\n',
      ),
      LegacyMessageTemplate(
        id: 'tpl_short',
        name: 'Short + clean',
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
        bodyTemplate: 'Legacy Packet: "{capsuleTitle}" ({date})',
      ),
    ];
  }

  Future<List<LegacyMessageTemplate>> listTemplates() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) {
      final defaults = _defaults();
      await _saveRaw(prefs, defaults);
      return defaults;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('not a list');
      final list = decoded
          .whereType<Map>()
          .map((e) => LegacyMessageTemplate.fromMap(e.cast<String, dynamic>()))
          .where((t) => t.id.isNotEmpty)
          .toList();

      // Ensure built-in defaults exist (non-destructive).
      final byId = {for (final t in list) t.id: t};
      for (final d in _defaults()) {
        byId.putIfAbsent(d.id, () => d);
      }
      final merged = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
      if (merged.length != list.length) {
        await _saveRaw(prefs, merged);
      }
      return merged;
    } catch (_) {
      final defaults = _defaults();
      await _saveRaw(prefs, defaults);
      return defaults;
    }
  }

  Future<void> upsertTemplate(LegacyMessageTemplate template) async {
    final all = await listTemplates();
    final now = DateTime.now();
    final updated = template.copyWith(updatedAt: now, createdAt: template.createdAt);

    final next = <LegacyMessageTemplate>[];
    bool replaced = false;
    for (final t in all) {
      if (t.id == updated.id) {
        next.add(updated);
        replaced = true;
      } else {
        next.add(t);
      }
    }
    if (!replaced) next.add(updated);
    await _save(next);
  }

  Future<void> deleteTemplate(String id) async {
    final all = await listTemplates();
    final next = all.where((t) => t.id != id || t.isBuiltIn).toList();
    await _save(next);
  }

  Future<void> resetToDefaults() async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.remove(_kKey);
  }

  Future<void> _save(List<LegacyMessageTemplate> list) async {
    final prefs = NeuraPrefsCache.prefs;
    await _saveRaw(prefs, list);
  }

  Future<void> _saveRaw(SharedPreferences prefs, List<LegacyMessageTemplate> list) async {
    final payload = list.map((t) => t.toMap()).toList();
    await prefs.setString(_kKey, jsonEncode(payload));
  }
}
