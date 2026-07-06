import 'dart:convert';
/// A single sleep log entry.
import 'startup/neura_prefs_cache.dart';

class SleepEntry {
  final DateTime bedtime;
  final DateTime wakeTime;
  final int qualityRating; // 1-5
  final String? note;

  const SleepEntry({
    required this.bedtime,
    required this.wakeTime,
    required this.qualityRating,
    this.note,
  });

  Duration get duration => wakeTime.difference(bedtime);

  Map<String, dynamic> toJson() => {
        'bedtime': bedtime.toIso8601String(),
        'wakeTime': wakeTime.toIso8601String(),
        'qualityRating': qualityRating,
        'note': note,
      };

  factory SleepEntry.fromJson(Map<String, dynamic> m) => SleepEntry(
        bedtime:
            DateTime.tryParse(m['bedtime'] as String? ?? '') ?? DateTime.now(),
        wakeTime:
            DateTime.tryParse(m['wakeTime'] as String? ?? '') ?? DateTime.now(),
        qualityRating: (m['qualityRating'] as num?)?.toInt() ?? 3,
        note: m['note'] as String?,
      );
}

/// Persists sleep entries locally.
class SleepTrackerService {
  SleepTrackerService._();
  static final instance = SleepTrackerService._();

  static const _key = 'neura_sleep_v1';
  List<SleepEntry> _entries = [];

  List<SleepEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _entries = list
          .whereType<Map<String, dynamic>>()
          .map(SleepEntry.fromJson)
          .toList();
      _entries.sort((a, b) => b.bedtime.compareTo(a.bedtime));
    } catch (_) {
      _entries = [];
    }
  }

  Future<void> _save() async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(
        _key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> addEntry(SleepEntry entry) async {
    _entries.insert(0, entry);
    await _save();
  }

  double? averageHoursLast(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final recent = _entries.where((e) => e.bedtime.isAfter(cutoff)).toList();
    if (recent.isEmpty) return null;
    final totalMinutes =
        recent.fold<int>(0, (sum, e) => sum + e.duration.inMinutes);
    return totalMinutes / recent.length / 60.0;
  }
}
