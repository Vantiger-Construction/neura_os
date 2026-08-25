import '../intelligence/capability_registry.dart';
import '../intelligence/models.dart';

enum NeuraSkillNetworkPolicy {
  none,
  localOnly,
  declaredHosts,
}

class NeuraSkillManifest {
  NeuraSkillManifest({
    required this.id,
    required this.version,
    required Iterable<String> capabilities,
    required Iterable<String> privateDataClasses,
    required Iterable<String> permissions,
    required this.networkPolicy,
    this.declaredHosts = const <String>[],
    this.allowedInSafeMode = false,
    this.signature = '',
  }) : capabilities = Set<String>.unmodifiable(capabilities),
       privateDataClasses = Set<String>.unmodifiable(privateDataClasses),
       permissions = Set<String>.unmodifiable(permissions),
       declaredHosts = Set<String>.unmodifiable(declaredHosts);

  final String id;
  final String version;
  final Set<String> capabilities;
  final Set<String> privateDataClasses;
  final Set<String> permissions;
  final NeuraSkillNetworkPolicy networkPolicy;
  final Set<String> declaredHosts;
  final bool allowedInSafeMode;
  final String signature;
}

abstract class NeuraSkillSignatureVerifier {
  Future<bool> verify(NeuraSkillManifest manifest);
}

class NeuraDenyAllSkillSignatureVerifier
    implements NeuraSkillSignatureVerifier {
  const NeuraDenyAllSkillSignatureVerifier();

  @override
  Future<bool> verify(NeuraSkillManifest manifest) async => false;
}

class NeuraSkillValidationResult {
  NeuraSkillValidationResult({
    required this.accepted,
    required Iterable<String> reasons,
  }) : reasons = List<String>.unmodifiable(reasons);

  final bool accepted;
  final List<String> reasons;
}

/// Validates manifests only. It never loads arbitrary Dart, shell, PowerShell,
/// or native code.
class NeuraSignedSkillValidator {
  NeuraSignedSkillValidator({
    required this.signatureVerifier,
    NeuraCapabilityRegistry? capabilityRegistry,
  }) : capabilityRegistry =
            capabilityRegistry ?? NeuraCapabilityRegistry();

  final NeuraSkillSignatureVerifier signatureVerifier;
  final NeuraCapabilityRegistry capabilityRegistry;

  Future<NeuraSkillValidationResult> validate(
    NeuraSkillManifest manifest,
  ) async {
    final reasons = <String>[];

    if (!_validId.hasMatch(manifest.id)) {
      reasons.add('Skill id is not a valid reverse-domain identifier.');
    }

    if (manifest.signature.trim().isEmpty) {
      reasons.add('A signed manifest is required.');
    } else if (!await signatureVerifier.verify(manifest)) {
      reasons.add('The manifest signature is not trusted.');
    }

    if (manifest.capabilities.isEmpty) {
      reasons.add('At least one declared capability is required.');
    }

    for (final capabilityId in manifest.capabilities) {
      final capability = capabilityRegistry.resolve(capabilityId);
      if (capability.id == 'unknown') {
        reasons.add('Unknown capability: $capabilityId.');
        continue;
      }

      if (capability.approvalMode == NeuraApprovalMode.blocked ||
          capability.risk == NeuraCapabilityRisk.critical ||
          capability.id == NeuraCapabilityRegistry.moveMoney) {
        reasons.add('Blocked capability: $capabilityId.');
      }
    }

    final prohibited = manifest.permissions.intersection(
      _prohibitedPermissions,
    );
    if (prohibited.isNotEmpty) {
      reasons.add(
        'Arbitrary code or unrestricted host access is not allowed: '
        '${prohibited.join(', ')}.',
      );
    }

    if (manifest.networkPolicy == NeuraSkillNetworkPolicy.declaredHosts) {
      if (manifest.declaredHosts.isEmpty) {
        reasons.add('Declared-host network access requires at least one host.');
      }
      if (manifest.declaredHosts.any(
        (host) => host.contains('*') || host.trim().isEmpty,
      )) {
        reasons.add('Wildcard or empty network hosts are not allowed.');
      }
    } else if (manifest.declaredHosts.isNotEmpty) {
      reasons.add('Hosts were declared while network access is disabled.');
    }

    if (manifest.allowedInSafeMode) {
      final unsafeCapability = manifest.capabilities.any(
        (id) =>
            id != NeuraCapabilityRegistry.surfaceSuggestion &&
            id != NeuraCapabilityRegistry.openAppModule,
      );
      if (unsafeCapability ||
          manifest.networkPolicy != NeuraSkillNetworkPolicy.none) {
        reasons.add(
          'Safe Mode skills must be local, read-only, and network-free.',
        );
      }
    }

    return NeuraSkillValidationResult(
      accepted: reasons.isEmpty,
      reasons: reasons,
    );
  }

  static final RegExp _validId = RegExp(
    r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9_-]*)+$',
  );

  static const Set<String> _prohibitedPermissions = {
    'arbitrary_code',
    'shell',
    'powershell',
    'native_library_load',
    'unrestricted_file_system',
    'unrestricted_network',
  };
}

class NeuraSkillHealth {
  const NeuraSkillHealth({
    required this.crashCount,
    required this.quarantined,
  });

  final int crashCount;
  final bool quarantined;
}

class NeuraSkillHealthRegistry {
  NeuraSkillHealthRegistry({
    this.quarantineThreshold = 3,
  });

  final int quarantineThreshold;
  final Map<String, int> _crashes = <String, int>{};
  final Set<String> _quarantined = <String>{};

  NeuraSkillHealth health(String skillId) {
    return NeuraSkillHealth(
      crashCount: _crashes[skillId] ?? 0,
      quarantined: _quarantined.contains(skillId),
    );
  }

  NeuraSkillHealth recordCrash(String skillId) {
    final next = (_crashes[skillId] ?? 0) + 1;
    _crashes[skillId] = next;
    if (next >= quarantineThreshold) {
      _quarantined.add(skillId);
    }
    return health(skillId);
  }

  void restore(String skillId) {
    _crashes.remove(skillId);
    _quarantined.remove(skillId);
  }

  void resetAfterDataWipe() {
    _crashes.clear();
    _quarantined.clear();
  }
}
