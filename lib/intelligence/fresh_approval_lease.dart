enum NeuraFreshApprovalLeaseState {
  active,
  notYetValid,
  insufficientLifetime,
  expired,
  revoked,
  consumed,
  missing,
  scopeMismatch,
}

/// Exact immutable identifiers for one reviewed Action Loom mutation.
///
/// Raw prompts, proposal copy, payload values, journal text, and private
/// records are deliberately excluded from this scope.
class NeuraFreshApprovalScope {
  const NeuraFreshApprovalScope({
    required this.actionId,
    required this.candidateId,
    required this.receiptId,
    required this.capabilityId,
  });

  final String actionId;
  final String candidateId;
  final String receiptId;
  final String capabilityId;

  bool matches(NeuraFreshApprovalScope other) {
    return actionId == other.actionId &&
        candidateId == other.candidateId &&
        receiptId == other.receiptId &&
        capabilityId == other.capabilityId;
  }
}

/// Short-lived approval evidence. It has no authority outside Action Loom.
class NeuraFreshApprovalLease {
  const NeuraFreshApprovalLease({
    required this.id,
    required this.scope,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
  });

  final String id;
  final NeuraFreshApprovalScope scope;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;

  bool get grantsExecutionAuthority => false;
}

class NeuraFreshApprovalDecision {
  const NeuraFreshApprovalDecision({
    required this.allowed,
    required this.state,
    required this.reason,
    this.leaseId,
  });

  final bool allowed;
  final NeuraFreshApprovalLeaseState state;
  final String reason;
  final String? leaseId;

  bool get grantsExecutionAuthority => false;
}

/// Privacy-bounded metadata suitable for Action Loom's local audit ledger.
class NeuraFreshApprovalMetadata {
  const NeuraFreshApprovalMetadata({
    required this.leaseId,
    required this.state,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    this.consumedAtUtc,
    this.revokedAtUtc,
  });

  final String leaseId;
  final NeuraFreshApprovalLeaseState state;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final DateTime? consumedAtUtc;
  final DateTime? revokedAtUtc;
}

class _NeuraFreshApprovalRecord {
  _NeuraFreshApprovalRecord(this.lease);

  final NeuraFreshApprovalLease lease;
  DateTime? consumedAtUtc;
  DateTime? revokedAtUtc;
}

/// Process-local registry for exact-scope, single-use approval evidence.
///
/// Leases expire quickly, are replaced on every new approval gesture, and are
/// consumed atomically immediately before the capability executor mutates
/// state. Missing, stale, revoked, replayed, or mismatched evidence fails
/// closed.
class NeuraFreshApprovalLeaseRegistry {
  NeuraFreshApprovalLeaseRegistry({
    this.maximumLifetime = const Duration(minutes: 2),
    this.maximumRecords = 100,
  }) {
    if (maximumLifetime.inMicroseconds <= 0) {
      throw ArgumentError.value(
        maximumLifetime,
        'maximumLifetime',
        'Fresh approval lifetime must be positive.',
      );
    }
    if (maximumRecords <= 0) {
      throw ArgumentError.value(
        maximumRecords,
        'maximumRecords',
        'At least one approval record slot is required.',
      );
    }
  }

  final Duration maximumLifetime;
  final int maximumRecords;

  final Map<String, _NeuraFreshApprovalRecord> _recordsByActionId =
      <String, _NeuraFreshApprovalRecord>{};
  int _nextSequence = 0;

  int get recordCount => _recordsByActionId.length;

  NeuraFreshApprovalLease issue({
    required NeuraFreshApprovalScope scope,
    required DateTime issuedAt,
    Duration lifetime = const Duration(minutes: 2),
    DateTime? notAfter,
  }) {
    _validateScope(scope);
    if (lifetime.inMicroseconds <= 0 || lifetime > maximumLifetime) {
      throw ArgumentError.value(
        lifetime,
        'lifetime',
        'Fresh approval lifetime must be positive and no longer than '
            '$maximumLifetime.',
      );
    }

    final issuedAtUtc = issuedAt.toUtc();
    var expiresAtUtc = issuedAtUtc.add(lifetime);
    final hardDeadline = notAfter?.toUtc();
    if (hardDeadline != null && hardDeadline.isBefore(expiresAtUtc)) {
      expiresAtUtc = hardDeadline;
    }
    if (!expiresAtUtc.isAfter(issuedAtUtc)) {
      throw StateError('The reviewed action expires before a lease can begin.');
    }

    revokeForAction(scope.actionId, now: issuedAtUtc);
    _pruneTerminalRecords(issuedAtUtc);
    if (_recordsByActionId.length >= maximumRecords &&
        !_recordsByActionId.containsKey(scope.actionId)) {
      throw StateError('The bounded fresh approval record limit was reached.');
    }

    final id = 'neura-fresh-${issuedAtUtc.microsecondsSinceEpoch}-'
        '${_nextSequence++}';
    final lease = NeuraFreshApprovalLease(
      id: id,
      scope: scope,
      issuedAtUtc: issuedAtUtc,
      expiresAtUtc: expiresAtUtc,
    );
    _recordsByActionId[scope.actionId] = _NeuraFreshApprovalRecord(lease);
    return lease;
  }

  NeuraFreshApprovalDecision validate({
    required NeuraFreshApprovalScope scope,
    required DateTime now,
    Duration minimumRemaining = Duration.zero,
  }) {
    return _evaluate(
      scope: scope,
      now: now,
      minimumRemaining: minimumRemaining,
      consume: false,
    );
  }

  NeuraFreshApprovalDecision validateAndConsume({
    required NeuraFreshApprovalScope scope,
    required DateTime now,
  }) {
    return _evaluate(
      scope: scope,
      now: now,
      minimumRemaining: Duration.zero,
      consume: true,
    );
  }

  NeuraFreshApprovalDecision _evaluate({
    required NeuraFreshApprovalScope scope,
    required DateTime now,
    required Duration minimumRemaining,
    required bool consume,
  }) {
    _validateScope(scope);
    if (minimumRemaining.isNegative) {
      throw ArgumentError.value(
        minimumRemaining,
        'minimumRemaining',
        'Minimum remaining lifetime cannot be negative.',
      );
    }

    final record = _recordsByActionId[scope.actionId];
    if (record == null) {
      return const NeuraFreshApprovalDecision(
        allowed: false,
        state: NeuraFreshApprovalLeaseState.missing,
        reason: 'A fresh approval is required for this action.',
      );
    }

    final current = now.toUtc();
    final state = _stateFor(record, current);
    if (state != NeuraFreshApprovalLeaseState.active) {
      return NeuraFreshApprovalDecision(
        allowed: false,
        state: state,
        reason: _reasonFor(state),
        leaseId: record.lease.id,
      );
    }
    if (!record.lease.scope.matches(scope)) {
      return NeuraFreshApprovalDecision(
        allowed: false,
        state: NeuraFreshApprovalLeaseState.scopeMismatch,
        reason: 'The fresh approval does not match this exact action.',
        leaseId: record.lease.id,
      );
    }
    if (minimumRemaining.inMicroseconds > 0 &&
        !current.add(minimumRemaining).isBefore(record.lease.expiresAtUtc)) {
      return NeuraFreshApprovalDecision(
        allowed: false,
        state: NeuraFreshApprovalLeaseState.insufficientLifetime,
        reason: 'The fresh approval is too close to expiry to start safely.',
        leaseId: record.lease.id,
      );
    }

    if (consume) {
      record.consumedAtUtc = current;
    }
    return NeuraFreshApprovalDecision(
      allowed: true,
      state: consume
          ? NeuraFreshApprovalLeaseState.consumed
          : NeuraFreshApprovalLeaseState.active,
      reason: consume
          ? 'The fresh approval was consumed for this exact action.'
          : 'The fresh approval matches this exact action.',
      leaseId: record.lease.id,
    );
  }

  bool revokeForAction(String actionId, {required DateTime now}) {
    final record = _recordsByActionId[actionId.trim()];
    if (record == null || record.consumedAtUtc != null) {
      return false;
    }
    record.revokedAtUtc ??= now.toUtc();
    return true;
  }

  NeuraFreshApprovalMetadata? metadataForAction(
    String actionId, {
    required DateTime now,
  }) {
    final record = _recordsByActionId[actionId.trim()];
    if (record == null) return null;
    return NeuraFreshApprovalMetadata(
      leaseId: record.lease.id,
      state: _stateFor(record, now.toUtc()),
      issuedAtUtc: record.lease.issuedAtUtc,
      expiresAtUtc: record.lease.expiresAtUtc,
      consumedAtUtc: record.consumedAtUtc,
      revokedAtUtc: record.revokedAtUtc,
    );
  }

  NeuraFreshApprovalLeaseState stateOf(
    String actionId, {
    required DateTime now,
  }) {
    final record = _recordsByActionId[actionId.trim()];
    if (record == null) return NeuraFreshApprovalLeaseState.missing;
    return _stateFor(record, now.toUtc());
  }

  void clear() {
    _recordsByActionId.clear();
    _nextSequence = 0;
  }

  NeuraFreshApprovalLeaseState _stateFor(
    _NeuraFreshApprovalRecord record,
    DateTime now,
  ) {
    if (record.revokedAtUtc != null) {
      return NeuraFreshApprovalLeaseState.revoked;
    }
    if (record.consumedAtUtc != null) {
      return NeuraFreshApprovalLeaseState.consumed;
    }
    if (now.isBefore(record.lease.issuedAtUtc)) {
      return NeuraFreshApprovalLeaseState.notYetValid;
    }
    if (!now.isBefore(record.lease.expiresAtUtc)) {
      return NeuraFreshApprovalLeaseState.expired;
    }
    return NeuraFreshApprovalLeaseState.active;
  }

  String _reasonFor(NeuraFreshApprovalLeaseState state) {
    switch (state) {
      case NeuraFreshApprovalLeaseState.notYetValid:
        return 'The fresh approval is not valid yet.';
      case NeuraFreshApprovalLeaseState.insufficientLifetime:
        return 'The fresh approval is too close to expiry to start safely.';
      case NeuraFreshApprovalLeaseState.expired:
        return 'The fresh approval expired before execution.';
      case NeuraFreshApprovalLeaseState.revoked:
        return 'The fresh approval was revoked.';
      case NeuraFreshApprovalLeaseState.consumed:
        return 'The fresh approval was already used.';
      case NeuraFreshApprovalLeaseState.missing:
        return 'A fresh approval is required for this action.';
      case NeuraFreshApprovalLeaseState.scopeMismatch:
        return 'The fresh approval does not match this exact action.';
      case NeuraFreshApprovalLeaseState.active:
        return 'The fresh approval is active.';
    }
  }

  void _validateScope(NeuraFreshApprovalScope scope) {
    final values = <String>[
      scope.actionId,
      scope.candidateId,
      scope.receiptId,
      scope.capabilityId,
    ];
    if (values.any(
      (value) =>
          value.trim().isEmpty ||
          value.contains('\n') ||
          value.contains('\r') ||
          value == '*',
    )) {
      throw ArgumentError(
        'Fresh approval scope identifiers must be explicit and bounded.',
      );
    }
  }

  void _pruneTerminalRecords(DateTime now) {
    if (_recordsByActionId.length < maximumRecords) return;
    final terminal = _recordsByActionId.entries
        .where(
          (entry) =>
              _stateFor(entry.value, now) !=
              NeuraFreshApprovalLeaseState.active,
        )
        .toList(growable: false)
      ..sort(
        (left, right) => left.value.lease.issuedAtUtc
            .compareTo(right.value.lease.issuedAtUtc),
      );
    for (final entry in terminal) {
      if (_recordsByActionId.length < maximumRecords) break;
      _recordsByActionId.remove(entry.key);
    }
  }
}
