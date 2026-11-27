import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/journal_entry.dart';
import '../modules/mood/mood_models.dart';
import '../modules/mood/mood_store.dart';
import '../profiles/local_profile_service.dart';
import '../relationships/services/crisis_text_scan.dart';
import '../startup/neura_prefs_cache.dart';
import 'emotion_analysis_service.dart';
import 'local_journal_store.dart';

/// A memory from a month or a year ago today.
class NeuraMemory {
  final String when;
  final String text;
  final DateTime day;

  const NeuraMemory(
      {required this.when, required this.text, required this.day});
}

/// On this day: now and then, a gentle look back at what the user wrote or
/// checked in a year (or a month) ago today.
///
/// Off until turned on, once a day at most, never in profile sessions. Only
/// days that were not hard come back uninvited: any check-in under 5/10, a
/// hard feeling in the journal, or crisis language keeps that day private.
class NeuraOnThisDay {
  NeuraOnThisDay({
    Future<List<MoodEntry>> Function()? moods,
    Future<List<JournalEntry>> Function()? journal,
    DateTime Function()? now,
  })  : _moods = moods ?? MoodStore.instance.getAll,
        _journal = journal ?? LocalJournalStore().loadEntries,
        _now = now ?? DateTime.now;

  static final NeuraOnThisDay instance = NeuraOnThisDay();

  @visibleForTesting
  static const enabledKey = 'neura.on_this_day.enabled';
  @visibleForTesting
  static const offeredKey = 'neura.on_this_day.offered';
  static const maxSnippet = 280;

  final Future<List<MoodEntry>> Function() _moods;
  final Future<List<JournalEntry>> Function() _journal;
  final DateTime Function() _now;

  bool get enabled => NeuraPrefsCache.prefsOrNull?.getBool(enabledKey) ?? false;

  Future<void> setEnabled(bool value) =>
      NeuraPrefsCache.prefs.setBool(enabledKey, value);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static const _hard = {
    'sadness',
    'grief',
    'loneliness',
    'shame',
    'anxiety',
    'overwhelm',
    'anger',
  };

  /// A memory worth offering from [day], or null when the day was hard or
  /// empty.
  static String? memoryOf(
    DateTime day,
    List<MoodEntry> moods,
    List<JournalEntry> journal,
  ) {
    final dayMoods = moods.where((m) => _sameDay(m.timestamp, day)).toList();
    final dayJournal = journal
        .where((j) => _sameDay(j.timestamp, day) && j.content.trim().isNotEmpty)
        .toList();
    if (dayMoods.any((m) => m.mood0to10 < 5)) return null;
    final texts = [
      ...dayJournal.map((j) => j.content.trim()),
      ...dayMoods.map((m) => m.note.trim()).where((n) => n.isNotEmpty),
    ];
    for (final text in texts) {
      if (CrisisTextScan.of(text).crisis) return null;
      final read = const EmotionAnalysisService().read(text);
      if (_hard.contains(read.primary) && read.intensity >= 0.4) return null;
      if (read.masked) return null;
    }
    if (texts.isNotEmpty) {
      final text = texts.first.replaceAll(RegExp(r'\s+'), ' ');
      return text.length <= maxSnippet
          ? text
          : '${text.substring(0, maxSnippet - 1).trimRight()}…';
    }
    if (dayMoods.isNotEmpty) {
      final best = dayMoods.map((m) => m.mood0to10).reduce(
            (a, b) => a > b ? a : b,
          );
      return 'You checked in at $best/10.';
    }
    return null;
  }

  /// Today's memory to offer, a year ago first, then a month ago. Null when
  /// off, already offered today, or nothing suitable.
  Future<NeuraMemory?> offer() async {
    if (!enabled || LocalProfileService.instance.enabled) return null;
    final now = _now();
    final today = now.toIso8601String().substring(0, 10);
    final prefs = NeuraPrefsCache.prefs;
    if (prefs.getString(offeredKey) == today) return null;
    await prefs.setString(offeredKey, today);
    final List<MoodEntry> moods;
    final List<JournalEntry> journal;
    try {
      moods = await _moods();
      journal = await _journal();
    } catch (_) {
      return null;
    }
    final candidates = <(String, DateTime)>[
      ('A year ago today', DateTime(now.year - 1, now.month, now.day)),
      ('A month ago today', DateTime(now.year, now.month - 1, now.day)),
    ];
    for (final (label, day) in candidates) {
      // DateTime rolls 31 March back to "31 February" = 3 March; skip it.
      if (day.day != now.day) continue;
      final text = memoryOf(day, moods, journal);
      if (text != null) return NeuraMemory(when: label, text: text, day: day);
    }
    return null;
  }
}
