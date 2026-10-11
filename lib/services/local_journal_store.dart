import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/journal_entry.dart';
import '../startup/neura_prefs_cache.dart';

/// Local journal authority shared by prompt, voice, and sync surfaces.
///
/// This store intentionally writes only to the existing local journal
/// preference key. Cloud sync remains an explicit, separate SyncService step.
class LocalJournalStore {
  LocalJournalStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  @visibleForTesting
  static const storageKey = 'journal_entries';

  final DateTime Function() _now;

  Future<List<JournalEntry>> loadEntries() async {
    final raw = NeuraPrefsCache.prefs.getStringList(storageKey) ?? const [];
    return raw
        .map(
          (encoded) =>
              JournalEntry.fromMap(jsonDecode(encoded) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> saveEntries(List<JournalEntry> entries) async {
    final sorted = entries.toList()
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final saved = await NeuraPrefsCache.prefs.setStringList(
      storageKey,
      sorted.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
    if (!saved) throw StateError('Local journal save could not be confirmed.');
  }

  Future<JournalEntry?> findById(String id) async {
    for (final entry in await loadEntries()) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<JournalEntry> upsertEntry({
    required String id,
    required String content,
    DateTime? timestamp,
    String moodTag = '',
    bool isVoice = false,
  }) async {
    if (id.trim().isEmpty || content.trim().isEmpty) {
      throw ArgumentError('Journal entries require an id and content.');
    }
    final entries = await loadEntries();
    final index = entries.indexWhere((entry) => entry.id == id);
    final existing = index == -1 ? null : entries[index];
    if (existing != null &&
        existing.content == content &&
        existing.moodTag == moodTag &&
        existing.isVoice == isVoice) {
      return existing;
    }

    final now = _now().toUtc();
    final next = JournalEntry(
      id: id,
      timestamp: existing?.timestamp ?? timestamp ?? now,
      updatedAt: now,
      content: content,
      moodTag: moodTag,
      isVoice: isVoice,
    );
    if (index == -1) {
      entries.add(next);
    } else {
      entries[index] = next;
    }
    await saveEntries(entries);
    return next;
  }
}
