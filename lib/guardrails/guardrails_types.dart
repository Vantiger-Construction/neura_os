enum ProposalType { prompt, suggestion, content, notification }

class NeuraContextSnapshot {
  final DateTime now;
  final int promptsLastHour;
  final int promptsLastDay;
  final bool userInFocusMode;
  final bool userSleepingMode;
  final bool userRecentlyDeclined;
  final bool isMinor;
  final double distressScore; // 0..1

  const NeuraContextSnapshot({
    required this.now,
    this.promptsLastHour = 0,
    this.promptsLastDay = 0,
    this.userInFocusMode = false,
    this.userSleepingMode = false,
    this.userRecentlyDeclined = false,
    this.isMinor = false,
    this.distressScore = 0,
  });
}

class NeuraProposal {
  final ProposalType type;
  final String id;
  final String message;
  final List<String> options; // must include "no_thanks"
  final Map<String, dynamic> payload;

  const NeuraProposal({
    required this.type,
    required this.id,
    required this.message,
    required this.options,
    this.payload = const {},
  });
}

class GuardrailDecision {
  final bool allow;
  final NeuraProposal? proposal;
  final String reason;
  final NeuraProposal? safeAlternative;

  const GuardrailDecision._({
    required this.allow,
    this.proposal,
    this.reason = '',
    this.safeAlternative,
  });

  factory GuardrailDecision.allow(NeuraProposal proposal) =>
      GuardrailDecision._(allow: true, proposal: proposal);

  factory GuardrailDecision.block(String reason,
          {NeuraProposal? safeAlternative}) =>
      GuardrailDecision._(
          allow: false, reason: reason, safeAlternative: safeAlternative);
}
