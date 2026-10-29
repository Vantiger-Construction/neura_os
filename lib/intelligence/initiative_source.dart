import 'capability_registry.dart';
import 'models.dart';
import 'routine_model.dart';

/// Neura's routine-aware initiative: candidates that come from *when* the
/// user shows up rather than from mood, focus, or quest signals.
///
/// Like `NeuraOpportunityRadar`, this is a pure proposal generator. It reads
/// no stores, schedules nothing, and executes nothing. Every candidate it
/// returns still has to pass the Autonomy Kernel (attention, privacy, room,
/// consent, constitution) and the app guardrails before it can surface, and
/// each one carries its own specialist id so the kernel's learned
/// specialist reputation adapts to whether the user welcomes it.
class NeuraInitiativeSource {
  const NeuraInitiativeSource({
    this.arrivalGap = const Duration(days: 3),
    this.minimumRoutineDays = 14,
    this.minimumRoutineOpens = 30,
    this.unusualShare = 0.02,
    this.lateNightStartHour = 0,
    this.lateNightEndHour = 5,
  })  : assert(minimumRoutineDays > 0),
        assert(minimumRoutineOpens > 0),
        assert(unusualShare >= 0 && unusualShare <= 1),
        assert(lateNightStartHour >= 0 && lateNightStartHour < 24),
        assert(lateNightEndHour > lateNightStartHour && lateNightEndHour <= 24);

  static const String arrivalSpecialist = 'initiative.arrival';
  static const String routineShiftSpecialist = 'initiative.routine_shift';

  /// Payload key naming which initiative produced a candidate.
  static const String kindKey = 'initiative_kind';
  static const String arrivalKind = 'arrival';
  static const String routineShiftKind = 'routine_shift';

  /// How long the user must have been away before a welcome-back card.
  final Duration arrivalGap;

  /// History required before an hour can be called "unusual".
  final int minimumRoutineDays;
  final int minimumRoutineOpens;

  /// An hour is unusual when fewer than this share of all opens fall near it.
  final double unusualShare;

  /// Local-hour window [start, end) where an unusual visit earns a gentle
  /// check-in. Outside it, an odd hour is just an odd hour.
  final int lateNightStartHour;
  final int lateNightEndHour;

  /// [routine] must be the history *before* the current app open is recorded,
  /// otherwise the current visit would count as its own precedent.
  List<NeuraIntelligenceCandidate> scan({
    required NeuraRoutineModel routine,
    required DateTime now,
  }) {
    if (!routine.matchesTimeZone(now) ||
        (routine.lastSeenAt != null && now.isBefore(routine.lastSeenAt!))) {
      return const [];
    }
    final candidates = <NeuraIntelligenceCandidate>[];
    final arrival = _arrival(routine, now);
    if (arrival != null) candidates.add(arrival);
    final shift = _routineShift(routine, now);
    if (shift != null) candidates.add(shift);
    return List<NeuraIntelligenceCandidate>.unmodifiable(candidates);
  }

  NeuraIntelligenceCandidate? _arrival(
    NeuraRoutineModel routine,
    DateTime now,
  ) {
    final lastSeen = routine.pendingArrivalFrom ?? routine.lastSeenAt;
    if (lastSeen == null) return null;
    final away = (routine.pendingArrivalAt ?? now).difference(lastSeen);
    if (away.isNegative || away < arrivalGap) return null;
    final days = away.inDays;

    return NeuraIntelligenceCandidate(
      // Keyed to the previous visit, so one absence yields one greeting.
      id: '$arrivalSpecialist:${lastSeen.millisecondsSinceEpoch}',
      capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
      specialistId: arrivalSpecialist,
      title: 'Welcome back',
      body: "It's been $days days. No catching up required. "
          "I'm glad you're here.",
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 2)),
      evidence: [
        NeuraEvidenceRef(
          id: 'routine.last_seen',
          source: 'routine_model',
          summary: 'Time since Neura was last opened.',
          observedAt: lastSeen,
          confidence: 1.0,
          sensitivity: NeuraSensitivity.routine,
        ),
      ],
      benefit: 0.6,
      urgency: 0.5,
      disruption: 0.2,
      confidence: 0.9,
      payload: <String, Object?>{kindKey: arrivalKind, 'days_away': days},
    );
  }

  NeuraIntelligenceCandidate? _routineShift(
    NeuraRoutineModel routine,
    DateTime now,
  ) {
    if (routine.distinctDays < minimumRoutineDays ||
        routine.totalCount < minimumRoutineOpens) {
      return null;
    }
    if (now.hour < lateNightStartHour || now.hour >= lateNightEndHour) {
      return null;
    }
    final lastSeen = routine.lastSeenAt;
    if (lastSeen != null && NeuraRoutineModel.sameHour(lastSeen, now)) {
      // Already here this hour; the check-in had its chance.
      return null;
    }
    if (routine.shareAround(now) >= unusualShare) return null;

    final confidence =
        (0.6 + 0.02 * (routine.distinctDays - minimumRoutineDays))
            .clamp(0.6, 0.85)
            .toDouble();

    return NeuraIntelligenceCandidate(
      id: '$routineShiftSpecialist:${NeuraRoutineModel.dayKey(now)}',
      capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
      specialistId: routineShiftSpecialist,
      title: 'Up later than usual',
      body: "You don't usually stop by at this hour. If something is keeping "
          'you up, I can help you wind down.',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      evidence: [
        NeuraEvidenceRef(
          id: 'routine.hour_of_week',
          source: 'routine_model',
          summary: 'How often Neura is opened around this hour.',
          observedAt: now,
          confidence: confidence,
          sensitivity: NeuraSensitivity.personal,
        ),
      ],
      benefit: 0.6,
      urgency: 0.45,
      disruption: 0.25,
      confidence: confidence,
      payload: const <String, Object?>{kindKey: routineShiftKind},
    );
  }
}
