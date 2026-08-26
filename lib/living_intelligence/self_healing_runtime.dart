enum NeuraReleaseSlot {
  slotA,
  slotB,
  recovery,
}

enum NeuraReleaseHealth {
  empty,
  candidate,
  healthy,
  failed,
  quarantined,
}

class NeuraReleaseCandidate {
  const NeuraReleaseCandidate({
    required this.version,
    required this.signatureVerified,
    required this.checksumVerified,
  });

  final String version;
  final bool signatureVerified;
  final bool checksumVerified;
}

class NeuraCanaryResult {
  const NeuraCanaryResult({
    required this.firstFrameRendered,
    required this.runtimePayloadComplete,
    required this.launchSentinelMatched,
    this.details = '',
  });

  final bool firstFrameRendered;
  final bool runtimePayloadComplete;
  final bool launchSentinelMatched;
  final String details;

  bool get passed =>
      firstFrameRendered && runtimePayloadComplete && launchSentinelMatched;
}

class NeuraReleaseSlotState {
  const NeuraReleaseSlotState({
    required this.slot,
    required this.health,
    this.version,
    this.failureCount = 0,
  });

  final NeuraReleaseSlot slot;
  final NeuraReleaseHealth health;
  final String? version;
  final int failureCount;

  NeuraReleaseSlotState copyWith({
    NeuraReleaseHealth? health,
    String? version,
    int? failureCount,
  }) {
    return NeuraReleaseSlotState(
      slot: slot,
      health: health ?? this.health,
      version: version ?? this.version,
      failureCount: failureCount ?? this.failureCount,
    );
  }
}

class NeuraPromotionDecision {
  const NeuraPromotionDecision({
    required this.promoted,
    required this.activeSlot,
    required this.reason,
  });

  final bool promoted;
  final NeuraReleaseSlot activeSlot;
  final String reason;
}

/// In-memory A/B release-state controller.
///
/// Platform installers provide the actual signed package verification, file
/// staging, and process launch. This controller owns deterministic promotion,
/// rollback, and quarantine decisions.
class NeuraSelfHealingRuntime {
  NeuraSelfHealingRuntime({
    this.quarantineThreshold = 2,
  }) : _slots = {
          NeuraReleaseSlot.slotA: const NeuraReleaseSlotState(
            slot: NeuraReleaseSlot.slotA,
            health: NeuraReleaseHealth.healthy,
            version: 'current',
          ),
          NeuraReleaseSlot.slotB: const NeuraReleaseSlotState(
            slot: NeuraReleaseSlot.slotB,
            health: NeuraReleaseHealth.empty,
          ),
          NeuraReleaseSlot.recovery: const NeuraReleaseSlotState(
            slot: NeuraReleaseSlot.recovery,
            health: NeuraReleaseHealth.healthy,
            version: 'recovery',
          ),
        };

  final int quarantineThreshold;
  final Map<NeuraReleaseSlot, NeuraReleaseSlotState> _slots;

  NeuraReleaseSlot _activeSlot = NeuraReleaseSlot.slotA;

  NeuraReleaseSlot get activeSlot => _activeSlot;

  NeuraReleaseSlotState state(NeuraReleaseSlot slot) => _slots[slot]!;

  NeuraReleaseSlot get inactiveApplicationSlot =>
      _activeSlot == NeuraReleaseSlot.slotA
          ? NeuraReleaseSlot.slotB
          : NeuraReleaseSlot.slotA;

  NeuraReleaseSlot installCandidate(NeuraReleaseCandidate candidate) {
    if (!candidate.signatureVerified || !candidate.checksumVerified) {
      throw StateError(
        'Candidate packages require verified signatures and checksums.',
      );
    }

    final target = inactiveApplicationSlot;
    final current = state(target);
    if (current.health == NeuraReleaseHealth.quarantined) {
      throw StateError('The inactive release slot is quarantined.');
    }

    _slots[target] = current.copyWith(
      health: NeuraReleaseHealth.candidate,
      version: candidate.version,
      failureCount: 0,
    );
    return target;
  }

  NeuraPromotionDecision evaluateCanary({
    required NeuraReleaseSlot candidateSlot,
    required NeuraCanaryResult result,
  }) {
    final candidate = state(candidateSlot);
    if (candidate.health != NeuraReleaseHealth.candidate) {
      return NeuraPromotionDecision(
        promoted: false,
        activeSlot: _activeSlot,
        reason: 'The selected slot does not contain a candidate release.',
      );
    }

    if (result.passed) {
      final previous = _activeSlot;
      _activeSlot = candidateSlot;
      _slots[candidateSlot] = candidate.copyWith(
        health: NeuraReleaseHealth.healthy,
        failureCount: 0,
      );

      final previousState = state(previous);
      if (previousState.health != NeuraReleaseHealth.quarantined) {
        _slots[previous] = previousState.copyWith(
          health: NeuraReleaseHealth.healthy,
        );
      }

      return NeuraPromotionDecision(
        promoted: true,
        activeSlot: _activeSlot,
        reason: 'The candidate passed the canary launch contract.',
      );
    }

    final failures = candidate.failureCount + 1;
    final nextHealth = failures >= quarantineThreshold
        ? NeuraReleaseHealth.quarantined
        : NeuraReleaseHealth.failed;

    _slots[candidateSlot] = candidate.copyWith(
      health: nextHealth,
      failureCount: failures,
    );

    return NeuraPromotionDecision(
      promoted: false,
      activeSlot: _activeSlot,
      reason: nextHealth == NeuraReleaseHealth.quarantined
          ? 'The failed candidate was quarantined.'
          : 'The candidate failed and the verified slot remains active.',
    );
  }

  void enterRecovery() {
    _activeSlot = NeuraReleaseSlot.recovery;
  }

  void clearQuarantine(NeuraReleaseSlot slot) {
    if (slot == NeuraReleaseSlot.recovery) {
      return;
    }
    _slots[slot] = NeuraReleaseSlotState(
      slot: slot,
      health: NeuraReleaseHealth.empty,
      failureCount: 0,
    );
  }
}
