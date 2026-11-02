import 'dart:math';

const _maxApprovalLifetime = Duration(minutes: 5);

/// A short-lived capability for exactly one native cloud-swarm operation.
///
/// The UI must create this only after showing the user what will be sent and
/// receiving a visible confirmation. The service consumes it immediately
/// before crossing into the native swarm; it cannot be reused for a retry,
/// another turn, background work, or a later session.
class NeuraSwarmApproval {
  NeuraSwarmApproval._({
    required this.issuedAt,
    required this.expiresAt,
    required this.id,
  });

  final DateTime issuedAt;
  final DateTime expiresAt;
  final String id;
  bool _consumed = false;

  static NeuraSwarmApproval grantFromVisibleConfirmation({
    DateTime? now,
    Duration lifetime = _maxApprovalLifetime,
  }) {
    if (lifetime <= Duration.zero || lifetime > _maxApprovalLifetime) {
      throw ArgumentError.value(
        lifetime,
        'lifetime',
        'must be greater than zero and no longer than five minutes',
      );
    }

    final issuedAt = (now ?? DateTime.now()).toUtc();
    final random = Random.secure();
    final id = List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();

    return NeuraSwarmApproval._(
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(lifetime),
      id: id,
    );
  }

  bool get isConsumed => _consumed;

  bool consume({
    required DateTime now,
    required bool foreground,
    required bool safeMode,
  }) {
    if (_consumed || !foreground || safeMode) return false;

    final current = now.toUtc();
    if (current.isBefore(issuedAt) || !current.isBefore(expiresAt)) {
      return false;
    }

    _consumed = true;
    return true;
  }
}
