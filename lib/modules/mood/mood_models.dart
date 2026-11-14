import 'dart:convert';

class MoodEntry {
  final DateTime timestamp;
  final int mood0to10;
  final String note;
  final int? energy0to10;
  final double? sleepHours;

  MoodEntry(
      {required this.timestamp,
      required this.mood0to10,
      required this.note,
      this.energy0to10,
      this.sleepHours}) {
    if (energy0to10 != null && (energy0to10! < 0 || energy0to10! > 10)) {
      throw ArgumentError.value(energy0to10, 'energy0to10');
    }
    if (sleepHours != null &&
        (!sleepHours!.isFinite || sleepHours! < 0 || sleepHours! > 24)) {
      throw ArgumentError.value(sleepHours, 'sleepHours');
    }
  }

  Map<String, Object?> toJson() => {
        'ts': timestamp.toUtc().toIso8601String(),
        'mood': mood0to10,
        'note': note,
        if (energy0to10 != null) 'energy': energy0to10,
        if (sleepHours != null) 'sleepHours': sleepHours,
      };

  static MoodEntry fromJson(Map<String, Object?> json) {
    return MoodEntry(
      timestamp: DateTime.parse((json['ts'] as String)).toLocal(),
      mood0to10: (json['mood'] as num).round(),
      note: (json['note'] as String?) ?? '',
      energy0to10: _energy(json['energy']),
      sleepHours: _sleep(json['sleepHours']),
    );
  }

  static List<MoodEntry> decodeList(String raw) {
    if (raw.trim().isEmpty) return <MoodEntry>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <MoodEntry>[];
    return decoded
        .whereType<Map>()
        .map((m) => MoodEntry.fromJson(Map<String, Object?>.from(m)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  static String encodeList(List<MoodEntry> items) {
    final data = items.map((e) => e.toJson()).toList();
    return jsonEncode(data);
  }

  // Invalid optional metadata must not discard an older entry or count as zero.
  static int? _energy(Object? value) => value is num &&
          value.isFinite &&
          value >= 0 &&
          value <= 10 &&
          value == value.roundToDouble()
      ? value.toInt()
      : null;
  static double? _sleep(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 24
          ? value.toDouble()
          : null;
}

/// Descriptive statistics, with separate denominators for optional fields.
class MoodSummary {
  MoodSummary(Iterable<MoodEntry> entries, DateTime now) {
    final start = now.subtract(const Duration(days: 7));
    final recent = entries
        .where((e) => !e.timestamp.isBefore(start) && !e.timestamp.isAfter(now))
        .toList();
    final moods =
        recent.map((e) => e.mood0to10).where((v) => v >= 0 && v <= 10).toList();
    final energy = recent.map((e) => e.energy0to10).whereType<int>().toList();
    final sleep = recent.map((e) => e.sleepHours).whereType<double>().toList();
    count = moods.length;
    energyCount = energy.length;
    sleepCount = sleep.length;
    moodAverage = _average(moods);
    energyAverage = _average(energy);
    sleepAverage = _average(sleep);
  }
  late final int count;
  late final int energyCount;
  late final int sleepCount;
  late final double? moodAverage;
  late final double? energyAverage;
  late final double? sleepAverage;
  static double? _average(List<num> values) => values.isEmpty
      ? null
      : values.fold<double>(0, (sum, value) => sum + value) / values.length;
}
