import 'models.dart';

/// Canonical capability catalog for Neura's approval boundary.
///
/// Model output, local specialists, and future plugins refer to capabilities
/// by id. Unknown ids resolve to a blocked, critical capability so a typo or
/// newly introduced tool cannot silently gain authority.
class NeuraCapabilityRegistry {
  NeuraCapabilityRegistry({Iterable<NeuraCapabilityDefinition>? capabilities})
      : _capabilities = {
          for (final capability in capabilities ?? builtIns)
            capability.id: capability,
        };

  static const surfaceSuggestion = 'surface_local_suggestion';
  static const openAppModule = 'open_app_module';
  static const changeLocalPlan = 'change_local_plan';
  static const scheduleNotification = 'schedule_notification';
  static const exportPrivateData = 'export_private_data';
  static const contactPerson = 'contact_person';
  static const moveMoney = 'move_money';

  static const builtIns = <NeuraCapabilityDefinition>[
    NeuraCapabilityDefinition(
      id: surfaceSuggestion,
      title: 'Surface an on-device suggestion',
      description:
          'Show a dismissible suggestion without changing data or leaving Neura.',
      risk: NeuraCapabilityRisk.readOnly,
      approvalMode: NeuraApprovalMode.none,
      reversible: true,
      hasExternalSideEffect: false,
    ),
    NeuraCapabilityDefinition(
      id: openAppModule,
      title: 'Open a Neura module',
      description:
          'Navigate only after the user taps the suggestion action.',
      risk: NeuraCapabilityRisk.reversibleLocal,
      approvalMode: NeuraApprovalMode.none,
      reversible: true,
      hasExternalSideEffect: false,
    ),
    NeuraCapabilityDefinition(
      id: changeLocalPlan,
      title: 'Change a local plan',
      description:
          'Create or modify a quest, ritual, goal, or schedule on this device.',
      risk: NeuraCapabilityRisk.reversibleLocal,
      approvalMode: NeuraApprovalMode.everyTime,
      reversible: true,
      hasExternalSideEffect: false,
    ),
    NeuraCapabilityDefinition(
      id: scheduleNotification,
      title: 'Schedule a notification',
      description:
          'Ask the operating system to show a reminder at a later time.',
      risk: NeuraCapabilityRisk.external,
      approvalMode: NeuraApprovalMode.everyTime,
      reversible: true,
      hasExternalSideEffect: true,
    ),
    NeuraCapabilityDefinition(
      id: exportPrivateData,
      title: 'Export private data',
      description:
          'Create a user-requested export containing private Neura records.',
      risk: NeuraCapabilityRisk.sensitiveLocal,
      approvalMode: NeuraApprovalMode.everyTime,
      reversible: false,
      hasExternalSideEffect: false,
    ),
    NeuraCapabilityDefinition(
      id: contactPerson,
      title: 'Contact another person',
      description:
          'Send or prepare communication addressed to somebody outside Neura.',
      risk: NeuraCapabilityRisk.external,
      approvalMode: NeuraApprovalMode.everyTime,
      reversible: false,
      hasExternalSideEffect: true,
    ),
    NeuraCapabilityDefinition(
      id: moveMoney,
      title: 'Move money',
      description:
          'Execute a financial transaction. Autonomous execution is disabled.',
      risk: NeuraCapabilityRisk.critical,
      approvalMode: NeuraApprovalMode.blocked,
      reversible: false,
      hasExternalSideEffect: true,
    ),
  ];

  static const _unknown = NeuraCapabilityDefinition(
    id: 'unknown',
    title: 'Unknown capability',
    description: 'Unregistered capabilities are blocked by default.',
    risk: NeuraCapabilityRisk.critical,
    approvalMode: NeuraApprovalMode.blocked,
    reversible: false,
    hasExternalSideEffect: true,
  );

  final Map<String, NeuraCapabilityDefinition> _capabilities;

  List<NeuraCapabilityDefinition> get all {
    final result = _capabilities.values.toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return List.unmodifiable(result);
  }

  NeuraCapabilityDefinition resolve(String id) =>
      _capabilities[id] ?? _unknown;
}
