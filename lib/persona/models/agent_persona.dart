import 'package:flutter/material.dart';

/// A named identity Neura can answer as. All agents share the same
/// [PersonaProfile] tone knobs (warmth/directness/humor/energy/depth) from
/// [NeuraPersonaService] -- agents differ by identity and role focus, not
/// by tone, to keep the persona-switching UI to a single set of sliders.
@immutable
class AgentPersona {
  final String id;
  final String displayName;
  final String tagline;
  final IconData icon;

  /// Replaces the old hardcoded "You are Neura, a personal AI companion."
  /// line in the system prompt.
  final String identityPrompt;

  /// Extra bullets appended under "Behavior rules" in the system prompt.
  final List<String> roleInstructions;

  /// [NeuraRoom.id] values this agent is the default for.
  final Set<String> defaultRoomIds;

  /// True for agents that never appear in the user-facing chat picker
  /// (e.g. the weekly summarist, which is invoked internally, not chatted with).
  final bool isInternal;

  const AgentPersona({
    required this.id,
    required this.displayName,
    required this.tagline,
    required this.icon,
    required this.identityPrompt,
    required this.roleInstructions,
    this.defaultRoomIds = const {},
    this.isInternal = false,
  });
}
