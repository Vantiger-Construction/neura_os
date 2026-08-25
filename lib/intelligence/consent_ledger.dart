import 'models.dart';

class NeuraConsentGrant {
  const NeuraConsentGrant({
    required this.capabilityId,
    required this.grantedAt,
    required this.expiresAt,
  });

  final String capabilityId;
  final DateTime grantedAt;
  final DateTime expiresAt;

  bool isActiveAt(DateTime now) => now.isBefore(expiresAt);
}

/// Session-only consent grants.
///
/// Sensitive and external capabilities deliberately never receive persistent
/// approval. Their capability definitions use `everyTime`, so the ledger
/// cannot turn a previous confirmation into silent future authority.
class NeuraConsentLedger {
  final Map<String, NeuraConsentGrant> _sessionGrants = {};

  List<NeuraConsentGrant> activeAt(DateTime now) {
    _sessionGrants.removeWhere((_, grant) => !grant.isActiveAt(now));
    return List.unmodifiable(_sessionGrants.values);
  }

  bool isGranted(
    NeuraCapabilityDefinition capability, {
    required DateTime now,
  }) {
    switch (capability.approvalMode) {
      case NeuraApprovalMode.none:
        return true;
      case NeuraApprovalMode.session:
        final grant = _sessionGrants[capability.id];
        return grant != null && grant.isActiveAt(now);
      case NeuraApprovalMode.everyTime:
      case NeuraApprovalMode.blocked:
        return false;
    }
  }

  bool grantForSession(
    NeuraCapabilityDefinition capability, {
    required DateTime now,
    Duration duration = const Duration(hours: 8),
  }) {
    if (capability.approvalMode != NeuraApprovalMode.session) return false;
    _sessionGrants[capability.id] = NeuraConsentGrant(
      capabilityId: capability.id,
      grantedAt: now,
      expiresAt: now.add(duration),
    );
    return true;
  }

  void revoke(String capabilityId) => _sessionGrants.remove(capabilityId);

  void clear() => _sessionGrants.clear();
}
