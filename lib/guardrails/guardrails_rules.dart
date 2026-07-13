import 'guardrails_types.dart';

class GuardrailRules {
  GuardrailDecision? hardBlock(NeuraContextSnapshot ctx, NeuraProposal p) {
    if (ctx.isMinor && (p.payload['adult_only'] == true)) {
      return GuardrailDecision.block(
        'Blocked age-gated content.',
        safeAlternative: NeuraProposal(
          type: ProposalType.content,
          id: 'safe_humor',
          message: 'Want a wholesome joke instead?',
          options: const ['yes', 'no_thanks'],
          payload: const {'adult_only': false},
        ),
      );
    }

    if (ctx.distressScore >= 0.85) {
      return GuardrailDecision.block(
        'High distress detected. Switching to support mode.',
        safeAlternative: NeuraProposal(
          type: ProposalType.suggestion,
          id: 'support_mode',
          message: 'I’m here. Want grounding, or would you prefer to reach out to someone you trust?',
          options: const ['grounding', 'contact_someone', 'resources', 'no_thanks'],
          payload: const {'mode': 'support'},
        ),
      );
    }

    final msg = p.message.toLowerCase();
    if ((p.payload['exclusive_language'] == true) || msg.contains('only i can help')) {
      return GuardrailDecision.block(
        'Exclusive/manipulative language blocked.',
        safeAlternative: NeuraProposal(
          type: p.type,
          id: '${p.id}_rephrased',
          message: 'Here are a few options that might help — and you can also reach out to people in your life if you want.',
          options: _ensureNoThanks(p.options),
          payload: p.payload,
        ),
      );
    }

    return null;
  }

  GuardrailDecision? softShape(NeuraContextSnapshot ctx, NeuraProposal p) {
    if (ctx.userInFocusMode && p.type == ProposalType.notification) {
      return GuardrailDecision.block(
        'User in focus mode. Suppressing notification.',
        safeAlternative: NeuraProposal(
          type: ProposalType.suggestion,
          id: 'queue_for_later',
          message: 'I can save this for later.',
          options: const ['save', 'no_thanks'],
          payload: const {'queue': true},
        ),
      );
    }

    if (p.type == ProposalType.prompt) {
      if (ctx.promptsLastHour >= 2) {
        return GuardrailDecision.block(
          'Too many prompts this hour.',
          safeAlternative: NeuraProposal(
            type: ProposalType.suggestion,
            id: 'quiet_mode_offer',
            message: 'Want quiet mode for a bit?',
            options: const ['yes', 'no_thanks'],
            payload: const {'quiet_mode': true},
          ),
        );
      }
      if (ctx.userRecentlyDeclined) {
        return GuardrailDecision.allow(
          NeuraProposal(
            type: ProposalType.suggestion,
            id: '${p.id}_softened',
            message: _soften(p.message),
            options: _ensureNoThanks(p.options),
            payload: p.payload,
          ),
        );
      }
    }

    if (!p.options.contains('no_thanks')) {
      return GuardrailDecision.allow(
        NeuraProposal(
          type: p.type,
          id: p.id,
          message: p.message,
          options: _ensureNoThanks(p.options),
          payload: p.payload,
        ),
      );
    }

    return null;
  }

  List<String> _ensureNoThanks(List<String> options) =>
      options.contains('no_thanks') ? options : [...options, 'no_thanks'];

  String _soften(String msg) {
    return msg
        .replaceAll(RegExp(r'\bmust\b', caseSensitive: false), 'might')
        .replaceAll(RegExp(r'\bshould\b', caseSensitive: false), 'could');
  }
}
