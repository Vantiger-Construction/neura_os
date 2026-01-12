import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/weekly_snapshot_entry.dart';

class WeeklySnapshotService {
  WeeklySnapshotService._internal();
  static final WeeklySnapshotService instance =
      WeeklySnapshotService._internal();

  static const _keySnapshots = 'weekly_snapshot_entries_v1';

  List<WeeklySnapshotEntry> _entries = [];
  bool _loaded = false;

  List<WeeklySnapshotEntry> get entries =>
      List.unmodifiable(_entries..sort((a, b) => a.date.compareTo(b.date)));

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySnapshots);
    if (raw == null) {
      _entries = [];
      _loaded = true;
      return;
    }
    try {
      final list = json.decode(raw);
      if (list is List) {
        _entries = list
            .whereType<Map<String, dynamic>>()
            .map((m) =>
                WeeklySnapshotEntry.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      } else {
        _entries = [];
      }
    } catch (e) {
      // Self-heal: if JSON is corrupted, clear and start fresh.
      _entries = [];
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySnapshots);
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _entries.map((e) => e.toMap()).toList();
    await prefs.setString(_keySnapshots, json.encode(list));
  }

  /// Log a daily snapshot. If an entry for [date] already exists (same yyyy-mm-dd),
  /// it will be replaced.
  Future<void> logDay({
    required DateTime date,
    required double moodScore,
    int stormsCount = 0,
    int ritualsCompleted = 0,
    bool usedCareMode = false,
    String note = '',
  }) async {
    await load();
    final normalized = DateTime(date.year, date.month, date.day);
    _entries.removeWhere((e) =>
        e.date.year == normalized.year &&
        e.date.month == normalized.month &&
        e.date.day == normalized.day);

    _entries.add(
      WeeklySnapshotEntry(
        date: normalized,
        moodScore: moodScore,
        stormsCount: stormsCount,
        ritualsCompleted: ritualsCompleted,
        usedCareMode: usedCareMode,
        note: note,
      ),
    );
    await _save();
  }

  /// Returns entries for the last 7 days (including today).
  Future<List<WeeklySnapshotEntry>> last7Days() async {
    await load();
    if (_entries.isEmpty) return [];
    final now = DateTime.now();
    final sevenDaysAgo =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    return _entries
        .where((e) => !e.date.isBefore(sevenDaysAgo))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Simple text summary for last 7 days.
  Future<String> buildWeeklySummaryText() async {
    final last7 = await last7Days();
    if (last7.isEmpty) {
      return 'No check-ins logged for this week yet. Even one tiny check-in counts.';
    }
    final moods = last7.map((e) => e.moodScore).toList();
    final avgMood =
        moods.isEmpty ? 0.0 : moods.reduce((a, b) => a + b) / moods.length;

    final totalStorms =
        last7.isEmpty ? 0 : last7.map((e) => e.stormsCount).reduce((a, b) => a + b);
    final totalRituals = last7.isEmpty
        ? 0
        : last7.map((e) => e.ritualsCompleted).reduce((a, b) => a + b);
    final careUsedCount = last7.where((e) => e.usedCareMode).length;

    final moodWord = avgMood >= 7
        ? 'mostly steady or positive'
        : avgMood >= 4
            ? 'up and down'
            : 'pretty heavy';

    return 'This week your mood has been $moodWord (average ${avgMood.toStringAsFixed(1)}/10). '
        'You logged $totalRituals rituals and weathered $totalStorms storms. '
        '${careUsedCount > 0 ? 'You used Care Mode $careUsedCount time(s), which is a sign of taking your feelings seriously.' : 'You haven\'t used Care Mode this week—remember it\'s there when things feel heavy.'}';
  }
}
