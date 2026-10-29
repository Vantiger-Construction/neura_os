/// Bounded, content-free memory of *when* Neura is opened.
///
/// This is the routine half of Neura's initiative: it lets her notice a
/// return after a long absence, or a visit at an hour she has almost never
/// seen. It stores only an hour-of-week histogram, a capped list of active
/// calendar days, and the last-seen timestamp. It never stores what was
/// said, which screen was open, or anything from journals or conversations.
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
  })  : hourOfWeekCounts = List<int>.unmodifiable(
          _normaliseCounts(hourOfWeekCounts),
        ),
        activeDays = List<String>.unmodifiable(_normaliseDays(activeDays));

  factory NeuraRoutineModel.empty() =>
      NeuraRoutineModel(hourOfWeekCounts: const <int>[]);

  /// One slot per hour of the week, Monday 00:00 first.
  static const int slotCount = 7 * 24;

  /// Only this many most-recent active days are kept.
  static const int maxActiveDays = 60;

  /// When the histogram grows past this, every slot is halved so old habits
  /// fade and current ones dominate.
  static const int maxTotalCount = 2000;

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
      return NeuraRoutineModel.empty().recordOpen(at);
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
    final returned =
        previous != null && at.difference(previous) >= const Duration(days: 3);
    return NeuraRoutineModel(
      hourOfWeekCounts: counts,
      activeDays: days,
      lastSeenAt: at,
      timeZoneId: zoneFor(at),
      pendingArrivalFrom: returned ? previous : pendingArrivalFrom,
      pendingArrivalAt: returned ? at : pendingArrivalAt,
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

    final rawDays = json['days'];
    final days = <String>[];
    if (rawDays is List) {
      for (final value in rawDays) {
        if (value is String) days.add(value);
      }
    }

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
    );
  }

  static List<int> _normaliseCounts(List<int> counts) {
    if (counts.length != slotCount) return List<int>.filled(slotCount, 0);
    return <int>[for (final count in counts) count < 0 ? 0 : count];
  }

  static final RegExp _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static List<String> _normaliseDays(Iterable<String> days) {
    final unique = days.where(_dayPattern.hasMatch).toSet().toList()..sort();
    if (unique.length <= maxActiveDays) return unique;
    return unique.sublist(unique.length - maxActiveDays);
  }
}
