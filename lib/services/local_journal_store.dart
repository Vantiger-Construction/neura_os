import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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
  static final _uuid = Uuid();

  final DateTime Function() _now;

  static String newEntryId(String prefix) {
    final cleanPrefix = prefix.trim();
    if (cleanPrefix.isEmpty ||
        cleanPrefix.codeUnits.any((unit) => unit < 0x21 || unit == 0x7f)) {
      throw ArgumentError('Journal entry id prefixes must be printable.');
    }
    return '${cleanPrefix}_${_uuid.v4()}';
  }

  static String datePart(DateTime time) {
    final local = DateTime(time.year, time.month, time.day);
    return local.toIso8601String().substring(0, 10);
  }

  static String journalPromptMoodTag(DateTime time) =>
      'journal_prompt:${datePart(time)}';

  static String legacyJournalPromptId(DateTime time) =>
      'journal_prompt_${datePart(time)}';

  static final _legacyPromptIdDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static bool isLegacyJournalPromptEntry(JournalEntry entry) {
    const prefix = 'journal_prompt_';
    const promptPrefix = 'Prompt:\n';
    const responseSeparator = '\n\nResponse:\n';
    if (entry.isVoice || entry.moodTag.isNotEmpty) return false;
    if (!entry.id.startsWith(prefix)) return false;
    final suffix = entry.id.substring(prefix.length);
    return _legacyPromptIdDate.hasMatch(suffix) &&
        entry.content.startsWith(promptPrefix) &&
        entry.content.contains(responseSeparator);
  }

  static bool isJournalPromptEntry(JournalEntry entry) =>
      !entry.isVoice &&
      (entry.moodTag.startsWith('journal_prompt:') ||
          isLegacyJournalPromptEntry(entry));

  static String journalPromptMoodTagForEntry(JournalEntry entry) {
    if (entry.moodTag.startsWith('journal_prompt:')) return entry.moodTag;
    return journalPromptMoodTag(entry.timestamp);
  }

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
    final encoded = sorted.map((entry) => jsonEncode(entry.toMap())).toList();
    try {
      final saved = await NeuraPrefsCache.prefs.setStringList(
        storageKey,
        encoded,
      );
      if (!saved) {
        throw StateError('Local journal save could not be confirmed.');
      }
      await NeuraPrefsCache.prefs.reload();
      final committed = NeuraPrefsCache.prefs.getStringList(storageKey);
      if (!listEquals(committed, encoded)) {
        throw StateError('Local journal save did not reach durable storage.');
      }
    } catch (error, stackTrace) {
      try {
        await NeuraPrefsCache.prefs.reload();
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<JournalEntry?> findById(String id) async {
    for (final entry in await loadEntries()) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<JournalEntry?> findLatestByMoodTag(String moodTag) async {
    final entries = await loadEntries();
    for (final entry in entries) {
      if (entry.moodTag == moodTag) return entry;
    }
    return null;
  }

  Future<JournalEntry?> findJournalPromptForDate(DateTime time) async {
    final moodTag = journalPromptMoodTag(time);
    final legacyId = legacyJournalPromptId(time);
    final entries = await loadEntries();
    for (final entry in entries) {
      if (!entry.isVoice && entry.moodTag == moodTag) return entry;
    }
    for (final entry in entries) {
      if (entry.id == legacyId && isLegacyJournalPromptEntry(entry)) {
        return entry;
      }
    }
    return null;
  }

  Future<List<JournalEntry>> findJournalPromptEntries() async {
    return (await loadEntries())
        .where(isJournalPromptEntry)
        .toList(growable: false);
  }

  Future<List<JournalEntry>> findAll({
    String? moodTagPrefix,
    bool? isVoice,
  }) async {
    return (await loadEntries()).where((entry) {
      if (isVoice != null && entry.isVoice != isVoice) return false;
      if (moodTagPrefix != null && !entry.moodTag.startsWith(moodTagPrefix)) {
        return false;
      }
      return true;
    }).toList(growable: false);
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
    var entries = await loadEntries();
    var index = entries.indexWhere((entry) => entry.id == id);
    final existing = index == -1 ? null : entries[index];
    if (existing != null &&
        existing.content == content &&
        existing.moodTag == moodTag &&
        existing.isVoice == isVoice) {
      await NeuraPrefsCache.prefs.reload();
      entries = await loadEntries();
      index = entries.indexWhere((entry) => entry.id == id);
      final committed = index == -1 ? null : entries[index];
      if (committed != null &&
          committed.content == content &&
          committed.moodTag == moodTag &&
          committed.isVoice == isVoice) {
        return committed;
      }
    }

    final now = _now().toUtc();
    final current = index == -1 ? null : entries[index];
    final next = JournalEntry(
      id: id,
      timestamp: current?.timestamp ?? timestamp ?? now,
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
