import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/memory/memory_crypto.dart';
import '../models/journal_entry.dart';
import '../modules/mood/mood_models.dart';
import '../modules/mood/mood_store.dart';
import '../profiles/local_profile_service.dart';
import '../relationships/services/crisis_text_scan.dart';
import '../startup/neura_prefs_cache.dart';
import 'local_journal_store.dart';
import 'neura_future_notes.dart';

/// Writes the local model's prompt and returns its screened reply, or null.
typedef NeuraReflectionWriter = Future<String?> Function(
  String system,
  String prompt,
);

/// An opt-in morning note about yesterday, written by the on-device model
/// from the user's own mood check-ins and journal entries.
///
/// - Off until the user turns it on; never in profile sessions.
/// - Runs on the first open of a new day (after [dayStartsAtHour]), on this
///   computer only. Chat conversations are not stored, so they are not used.
/// - Any crisis language in yesterday's notes means no reflection at all:
///   that is for the crisis support flow, not a cheerful summary.
/// - The note is encrypted with the device memory key; only today's note is
///   kept, and dismissing it hides it.
class NeuraMorningReflection {
  NeuraMorningReflection({
    Future<String> Function(Map<String, dynamic>)? encrypt,
    Future<Map<String, dynamic>> Function(String)? decrypt,
    Future<List<MoodEntry>> Function()? moods,
    Future<List<JournalEntry>> Function()? journal,
    Future<List<String>> Function(DateTime day)? brightSpots,
    DateTime Function()? now,
  })  : _encrypt = encrypt ??
            ((json) async => (await MemoryCrypto.demo()).encryptJson(json)),
        _decrypt = decrypt ??
            ((blob) async => (await MemoryCrypto.demo()).decryptJson(blob)),
        _moods = moods ?? MoodStore.instance.getAll,
        _journal = journal ?? LocalJournalStore().loadEntries,
        _brightSpots = brightSpots ?? NeuraFutureNotes.instance.brightSpotsOn,
        _now = now ?? DateTime.now;

  static final NeuraMorningReflection instance = NeuraMorningReflection();

  @visibleForTesting
  static const enabledKey = 'neura.morning_reflection.enabled';
  @visibleForTesting
  static const storageKey = 'neura.morning_reflection.v1';

  static const dayStartsAtHour = 4;
  static const maxSourceBytes = 2000;

  static const system = 'You are Neura, a warm companion. You write a short '
      'morning note to someone about their day yesterday, from their own '
      'check-ins and journal. Two or three gentle spoken sentences. Notice '
      'one bright spot or one pattern; do not diagnose, judge or lecture, and '
      'give advice only if it is small and kind. Do not invent anything that '
      'is not in their notes.';

  final Future<String> Function(Map<String, dynamic>) _encrypt;
  final Future<Map<String, dynamic>> Function(String) _decrypt;
  final Future<List<MoodEntry>> Function() _moods;
  final Future<List<JournalEntry>> Function() _journal;
  final Future<List<String>> Function(DateTime day) _brightSpots;
  final DateTime Function() _now;
  Future<String?>? _preparing;

  bool get enabled => NeuraPrefsCache.prefsOrNull?.getBool(enabledKey) ?? false;

  Future<void> setEnabled(bool value) async {
    await NeuraPrefsCache.prefs.setBool(enabledKey, value);
    if (!value) await NeuraPrefsCache.prefs.remove(storageKey);
  }

  static String _date(DateTime time) =>
      DateTime(time.year, time.month, time.day)
          .toIso8601String()
          .substring(0, 10);

  /// The calendar day a reflection at [now] looks back on.
  static DateTime yesterdayOf(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return day.subtract(const Duration(days: 1));
  }

  /// The model prompt for [day], or null when there is nothing to reflect on
  /// or anything in it trips the crisis scan.
  static String? promptFor(
    DateTime day,
    List<MoodEntry> moods,
    List<JournalEntry> journal, {
    List<String> brightSpots = const [],
  }) {
    bool sameDay(DateTime time) =>
        time.year == day.year && time.month == day.month && time.day == day.day;
    final lines = <String>[];
    for (final entry in moods.where((m) => sameDay(m.timestamp))) {
      final parts = <String>['mood ${entry.mood0to10}/10'];
      if (entry.energy0to10 != null) {
        parts.add('energy ${entry.energy0to10}/10');
      }
      if (entry.sleepHours != null) parts.add('slept ${entry.sleepHours}h');
      final note = entry.note.trim();
      lines.add('Check-in: ${parts.join(', ')}'
          '${note.isEmpty ? '' : '. Note: $note'}');
    }
    for (final entry in journal.where((j) => sameDay(j.timestamp))) {
      final text = entry.content.trim();
      if (text.isNotEmpty) lines.add('Journal: $text');
    }
    for (final spot in brightSpots) {
      final text = spot.trim();
      if (text.isNotEmpty) lines.add('A bright spot they kept: $text');
    }
    if (lines.isEmpty) return null;
    if (lines.any((line) => CrisisTextScan.of(line).crisis)) return null;
    final kept = <String>[];
    var bytes = 0;
    for (final line in lines) {
      final size = utf8.encode(line).length + 1;
      if (bytes + size > maxSourceBytes) break;
      kept.add(line);
      bytes += size;
    }
    if (kept.isEmpty) return null;
    return 'Their notes from yesterday:\n${kept.join('\n')}\n\n'
        'Write the morning note now.';
  }

  /// Today's undismissed note, if one was written.
  Future<String?> todayNote() async {
    if (!enabled || LocalProfileService.instance.enabled) return null;
    final stored = await _read();
    if (stored == null ||
        stored['date'] != _date(_now()) ||
        stored['dismissed'] == true) {
      return null;
    }
    final text = stored['text'];
    return text is String && text.trim().isNotEmpty ? text : null;
  }

  Future<Map<String, dynamic>?> _read() async {
    final blob = NeuraPrefsCache.prefs.getString(storageKey);
    if (blob == null) return null;
    try {
      return await _decrypt(blob);
    } catch (_) {
      return null;
    }
  }

  Future<void> dismiss() async {
    final stored = await _read();
    if (stored == null) return;
    await NeuraPrefsCache.prefs.setString(
      storageKey,
      await _encrypt({...stored, 'dismissed': true}),
    );
  }

  /// Writes today's note if it is due, returning it (or null). At most one
  /// attempt per day, even when the model fails or there is nothing to say.
  Future<String?> prepareIfDue(NeuraReflectionWriter write) =>
      _preparing ??= _prepare(write).whenComplete(() => _preparing = null);

  Future<String?> _prepare(NeuraReflectionWriter write) async {
    if (!enabled || LocalProfileService.instance.enabled) return null;
    final now = _now();
    if (now.hour < dayStartsAtHour) return null;
    final today = _date(now);
    final stored = await _read();
    if (stored != null && stored['date'] == today) return todayNote();
    // Claim the day first, so a failure is not retried on every open.
    await NeuraPrefsCache.prefs.setString(
      storageKey,
      await _encrypt({'date': today, 'text': '', 'dismissed': false}),
    );
    final day = yesterdayOf(now);
    List<String> spots;
    try {
      spots = await _brightSpots(day);
    } catch (_) {
      spots = const [];
    }
    final prompt = promptFor(
      day,
      await _moods(),
      await _journal(),
      brightSpots: spots,
    );
    if (prompt == null) return null;
    String? text;
    try {
      text = (await write(system, prompt))?.trim();
    } catch (_) {
      return null;
    }
    if (text == null || text.isEmpty) return null;
    if (!enabled || LocalProfileService.instance.enabled) return null;
    await NeuraPrefsCache.prefs.setString(
      storageKey,
      await _encrypt({'date': today, 'text': text, 'dismissed': false}),
    );
    return text;
  }
}
