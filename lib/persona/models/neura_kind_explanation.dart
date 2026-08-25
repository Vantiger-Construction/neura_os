/// Shared client-first language for Neura's non-chat explanations.
///
/// This keeps proactive UI and spoken briefings warm and transparent without
/// changing scoring, eligibility, consent, or execution policy.
abstract final class NeuraKindExplanation {
  static const uncertainty =
      'I may not have the full picture, so please choose what feels right for you.';

  static String controlStatement({required bool requiresApproval}) {
    return requiresApproval
        ? 'This is only a suggestion. I will wait for your approval before making any change.'
        : 'This is only a suggestion. Nothing will happen unless you choose to open it.';
  }

  static String spokenBrief({
    required String title,
    required String body,
    required bool requiresApproval,
  }) {
    return '$title. $body. $uncertainty '
        '${controlStatement(requiresApproval: requiresApproval)}';
  }
}
