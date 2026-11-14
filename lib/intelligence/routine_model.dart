/// Bounded, content-free memory of *when* Neura is opened.
///
/// This is the routine half of Neura's initiative: it lets her notice a
/// return after a long absence, or a visit at an hour she has almost never
/// seen. It stores only an hour-of-week histogram, a capped list of active
/// calendar days, a capped list of recent nights with a visit after
/// midnight (date keys only), and the last-seen timestamp. It never stores
/// what was said, which screen was open, or anything from journals or
/// conversations.
///
/// Pure and immutable so it can be unit tested without Flutter or storage.
/// Times are interpreted in whatever zone the caller passes; the dashboard
/// passes local time, which is what "a usual hour" means to the user.
class NeuraRoutineModel {
  NeuraRoutineModel({
    required List<int> hourOfWeekCounts,
    Iterable<String> activeDays = const <String>[],
    this.lastSeenAt,
    this.timeZoneId,
    this.pendingArrivalFrom,
    this.pendingArrivalAt,
    Iterable<String> lateNights = const <String>[],
    String? windDownOfferedDay,
  })  : hourOfWeekCounts = List<int>.unmodifiable(
          _normaliseCounts(hourOfWeekCounts),
        ),
        activeDays = List<String>.unmodifiable(_normaliseDays(activeDays)),
        lateNights = List<String>.unmodifiable(
          _normaliseDays(lateNights, max: maxLateNights),
        ),
        windDownOfferedDay = _validDay(windDownOfferedDay);

  factory NeuraRoutineModel.empty() =>
      NeuraRoutineModel(hourOfWeekCounts: const <int>[]);

  /// One slot per hour of the week, Monday 00:00 first.
  static const int slotCount = 7 * 24;

  /// Only this many most-recent active days are kept.
  static const int maxActiveDays = 60;

  /// When the histogram grows past this, every slot is halved so old habits
  /// fade and current ones dominate.
  static const int maxTotalCount = 2000;

  /// Only this many most-recent late nights are kept.
  static const int maxLateNights = 14;

  /// A visit before this local hour belongs to the previous evening's night.
  static const int lateNightEndHour = 5;

  /// Schema 2 gained the optional `late_nights` and `wind_down_day` fields
  /// without a version bump: older readers ignore them, and missing fields
  /// read as empty, so existing routine history is kept.
  static const int schemaVersion = 2;

  final List<int> hourOfWeekCounts;

  /// Ascending `yyyy-mm-dd` keys of days Neura was opened.
  final List<String> activeDays;

  final DateTime? lastSeenAt;
  final String? timeZoneId;

  /// An absence remains eligible until its welcome card reaches a frame.
  /// Recording suppressed opens must not consume this opportunity.
  final DateTime? pendingArrivalFrom;
  final DateTime? pendingArrivalAt;

  /// Ascending night keys: the `yyyy-mm-dd` of the evening a night started,
  /// for nights when Neura was opened between midnight and
  /// [lateNightEndHour]. Dates only; no times, counts or content.
  final List<String> lateNights;

  /// The day key of the evening a wind-down card last reached a frame.
  final String? windDownOfferedDay;

  /// The night [at] belongs to when it falls after midnight and before
  /// [lateNightEndHour], or null for any other hour.
  static String? nightKeyFor(DateTime at) {
    if (at.hour >= lateNightEndHour) return null;
    return dayKey(DateTime(at.year, at.month, at.day - 1));
  }

  /// Late nights among the [nights] evenings before the evening of [at].
  /// The night that is about to start tonight is never counted.
  int lateNightsBefore(DateTime at, {int nights = 7}) {
    final newest = dayKey(DateTime(at.year, at.month, at.day - 1));
    final oldest = dayKey(DateTime(at.year, at.month, at.day - nights));
    var count = 0;
    for (final night in lateNights) {
      if (night.compareTo(oldest) >= 0 && night.compareTo(newest) <= 0) {
        count += 1;
      }
    }
    return count;
  }

  /// Whole days from [windDownOfferedDay] to the calendar day of [at], or
  /// null when no wind-down card has been shown.
  int? daysSinceWindDownOffer(DateTime at) {
    final offered = windDownOfferedDay;
    if (offered == null) return null;
    final parts = offered.split('-').map(int.parse).toList(growable: false);
    final offeredDate = DateTime.utc(parts[0], parts[1], parts[2]);
    final today = DateTime.utc(at.year, at.month, at.day);
    return today.difference(offeredDate).inDays;
  }

  static String zoneFor(DateTime at) =>
      '${at.timeZoneName}:${at.timeZoneOffset.inMinutes}';

  bool matchesTimeZone(DateTime at) => timeZoneId == zoneFor(at);

  int get totalCount => hourOfWeekCounts.fold(0, (sum, count) => sum + count);

  int get distinctDays => activeDays.length;

  static int slotFor(DateTime at) => (at.weekday - 1) * 24 + at.hour;

  static String dayKey(DateTime at) {
    final year = at.year.toString().padLeft(4, '0');
    final month = at.month.toString().padLeft(2, '0');
    final day = at.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static bool sameHour(DateTime a, DateTime b) {
    // Persisted timestamps are UTC; compare both instants in b's local zone.
    final offset = b.timeZoneOffset.inMilliseconds;
    const hour = Duration.millisecondsPerHour;
    return (a.millisecondsSinceEpoch + offset) ~/ hour ==
        (b.millisecondsSinceEpoch + offset) ~/ hour;
  }

  /// Returns a new model with an app open at [at] recorded.
  ///
  /// Repeated opens inside the same clock hour count once, so a dashboard
  /// that rebuilds several times does not look like a strong habit. A clock
  /// that moved backwards is ignored rather than rewriting history.
  NeuraRoutineModel recordOpen(DateTime at) {
    if (timeZoneId != null && !matchesTimeZone(at)) {
      // Local-hour slots cannot be compared across travel or DST changes.
      // The wind-down cooldown is a date, not an hour, so it survives the
      // reset; otherwise travel could bring the offer back early.
      return NeuraRoutineModel(
        hourOfWeekCounts: const <int>[],
        windDownOfferedDay: windDownOfferedDay,
      ).recordOpen(at);
    }
    final previous = lastSeenAt;
    if (previous != null && at.isBefore(previous)) return this;

    final counts = List<int>.of(hourOfWeekCounts);
    if (previous == null || !sameHour(previous, at)) {
      counts[slotFor(at)] += 1;
      if (counts.fold(0, (sum, count) => sum + count) > maxTotalCount) {
        for (var i = 0; i < counts.length; i++) {
          counts[i] = counts[i] ~/ 2;
        }
      }
    }

    final day = dayKey(at);
    final days =
        activeDays.contains(day) ? activeDays : <String>[...activeDays, day];
    final night = nightKeyFor(at);
    final nights = night == null || lateNights.contains(night)
        ? lateNights
        : <String>[...lateNights, night];
    final returned =
        previous != null && at.difference(previous) >= const Duration(days: 3);
    return NeuraRoutineModel(
      hourOfWeekCounts: counts,
      activeDays: days,
      lastSeenAt: at,
      timeZoneId: zoneFor(at),
      pendingArrivalFrom: returned ? previous : pendingArrivalFrom,
      pendingArrivalAt: returned ? at : pendingArrivalAt,
      lateNights: nights,
      windDownOfferedDay: windDownOfferedDay,
    );
  }

  NeuraRoutineModel acknowledgeArrival(String candidateId) {
    final from = pendingArrivalFrom;
    if (from == null ||
        candidateId != 'initiative.arrival:${from.millisecondsSinceEpoch}') {
      return this;
    }
    return NeuraRoutineModel(
      hourOfWeekCounts: hourOfWeekCounts,
      activeDays: activeDays,
      lastSeenAt: lastSeenAt,
      timeZoneId: timeZoneId,
      lateNights: lateNights,
      windDownOfferedDay: windDownOfferedDay,
    );
  }

  /// Records that the wind-down card for [candidateId] reached a frame, so
  /// the weekly cooldown survives restarts. The id carries the evening's
  /// day key (`initiative.wind_down:yyyy-mm-dd`); anything else is ignored.
  NeuraRoutineModel acknowledgeWindDown(String candidateId) {
    const prefix = 'initiative.wind_down:';
    if (!candidateId.startsWith(prefix)) return this;
    final day = candidateId.substring(prefix.length);
    if (!_isRealDay(day)) return this;
    return NeuraRoutineModel(
      hourOfWeekCounts: hourOfWeekCounts,
      activeDays: activeDays,
      lastSeenAt: lastSeenAt,
      timeZoneId: timeZoneId,
      pendingArrivalFrom: pendingArrivalFrom,
      pendingArrivalAt: pendingArrivalAt,
      lateNights: lateNights,
      windDownOfferedDay: day,
    );
  }

  /// Share of all recorded opens that fell in the hour around [at] (the hour
  /// itself plus one either side, wrapping across the week), so an open at
  /// 9:55 is not "unusual" for someone who always arrives at 10:05.
  /// Returns 0 when there is no history.
  double shareAround(DateTime at) {
    if (!matchesTimeZone(at)) return 0;
    final total = totalCount;
    if (total == 0) return 0;
    final slot = slotFor(at);
    final nearby = hourOfWeekCounts[(slot - 1 + slotCount) % slotCount] +
        hourOfWeekCounts[slot] +
        hourOfWeekCounts[(slot + 1) % slotCount];
    return nearby / total;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'v': schemaVersion,
        'hour_of_week': hourOfWeekCounts,
        'days': activeDays,
        'last_seen_ms': lastSeenAt?.millisecondsSinceEpoch,
        'zone': timeZoneId,
        'arrival_from_ms': pendingArrivalFrom?.millisecondsSinceEpoch,
        'arrival_at_ms': pendingArrivalAt?.millisecondsSinceEpoch,
        'late_nights': lateNights,
        'wind_down_day': windDownOfferedDay,
      };

  /// Never throws. Unknown versions or malformed fields fall back to an
  /// empty history rather than guessing.
  factory NeuraRoutineModel.fromJson(Map<String, Object?> json) {
    if (json['v'] != schemaVersion) return NeuraRoutineModel.empty();

    final rawCounts = json['hour_of_week'];
    final counts = <int>[];
    if (rawCounts is List) {
      for (final value in rawCounts) {
        counts.add(value is num && value.isFinite ? value.toInt() : 0);
      }
    }

    List<String> dayKeys(String key) {
      final raw = json[key];
      if (raw is! List) return const <String>[];
      return <String>[
        for (final value in raw)
          if (value is String) value,
      ];
    }

    final days = dayKeys('days');
    final nights = dayKeys('late_nights');
    final windDownDay = json['wind_down_day'];

    DateTime? timestamp(String key) {
      final raw = json[key];
      if (raw is! num || !raw.isFinite || raw.abs() > 8640000000000000) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
    }

    final zone = json['zone'];
    // v1 had no timezone provenance and is deliberately not used for inference.
    if (zone is! String || zone.isEmpty) return NeuraRoutineModel.empty();
    final lastSeen = timestamp('last_seen_ms');
    final arrivalFrom = timestamp('arrival_from_ms');
    final arrivalAt = timestamp('arrival_at_ms');
    final validArrival = arrivalFrom != null &&
        arrivalAt != null &&
        lastSeen != null &&
        !arrivalAt.isAfter(lastSeen) &&
        arrivalAt.difference(arrivalFrom) >= const Duration(days: 3);

    return NeuraRoutineModel(
      hourOfWeekCounts: counts,
      activeDays: days,
      lastSeenAt: lastSeen,
      timeZoneId: zone,
      pendingArrivalFrom: validArrival ? arrivalFrom : null,
      pendingArrivalAt: validArrival ? arrivalAt : null,
      lateNights: nights,
      windDownOfferedDay: windDownDay is String ? windDownDay : null,
    );
  }

  static List<int> _normaliseCounts(List<int> counts) {
    if (counts.length != slotCount) return List<int>.filled(slotCount, 0);
    return <int>[for (final count in counts) count < 0 ? 0 : count];
  }

  static final RegExp _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String? _validDay(String? day) =>
      day != null && _isRealDay(day) ? day : null;

  /// A `yyyy-mm-dd` key naming a date that exists, so `2026-13-45` or
  /// `2026-02-30` can't be counted or normalised into another day.
  static bool _isRealDay(String day) {
    if (!_dayPattern.hasMatch(day)) return false;
    final year = int.parse(day.substring(0, 4));
    final month = int.parse(day.substring(5, 7));
    final date = int.parse(day.substring(8, 10));
    final parsed = DateTime.utc(year, month, date);
    return parsed.year == year && parsed.month == month && parsed.day == date;
  }

  static List<String> _normaliseDays(
    Iterable<String> days, {
    int max = maxActiveDays,
  }) {
    final unique = days.where(_isRealDay).toSet().toList()..sort();
    if (unique.length <= max) return unique;
    return unique.sublist(unique.length - max);
  }
}
