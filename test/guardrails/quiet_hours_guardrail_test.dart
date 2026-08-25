import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/guardrails/guardrails.dart';
import 'package:neuro_companion/guardrails/guardrails_types.dart';

void main() {
  final guardrails = Guardrails();
  final now = DateTime.utc(2026, 8, 14, 23);

  group('quiet-hours guardrail', () {
    test('suppresses prompts, suggestions, and notifications', () {
      final context = NeuraContextSnapshot(
        now: now,
        userSleepingMode: true,
      );

      for (final type in <ProposalType>[
        ProposalType.prompt,
        ProposalType.suggestion,
        ProposalType.notification,
      ]) {
        final decision = guardrails.evaluate(
          context: context,
          proposal: _proposal(type),
        );

        expect(decision.allow, isFalse, reason: '$type must be suppressed');
        expect(decision.reason, contains('Quiet hours'));
      }
    });

    test('does not suppress passive content', () {
      final decision = guardrails.evaluate(
        context: NeuraContextSnapshot(
          now: now,
          userSleepingMode: true,
        ),
        proposal: _proposal(ProposalType.content),
      );

      expect(decision.allow, isTrue);
    });
  });

  group('focus guardrail', () {
    test('suppresses prompts and notifications', () {
      final context = NeuraContextSnapshot(
        now: now,
        userInFocusMode: true,
      );

      for (final type in <ProposalType>[
        ProposalType.prompt,
        ProposalType.notification,
      ]) {
        final decision = guardrails.evaluate(
          context: context,
          proposal: _proposal(type),
        );

        expect(decision.allow, isFalse, reason: '$type must be suppressed');
        expect(decision.reason, contains('focus mode'));
        expect(decision.safeAlternative?.id, 'queue_for_later');
      }
    });

    test('allows a normal suggestion', () {
      final focused = guardrails.evaluate(
        context: NeuraContextSnapshot(
          now: now,
          userInFocusMode: true,
        ),
        proposal: _proposal(ProposalType.suggestion),
      );
      final normal = guardrails.evaluate(
        context: NeuraContextSnapshot(now: now),
        proposal: _proposal(ProposalType.suggestion),
      );

      expect(focused.allow, isTrue);
      expect(normal.allow, isTrue);
    });
  });
}

NeuraProposal _proposal(ProposalType type) => NeuraProposal(
      type: type,
      id: 'test-${type.name}',
      message: 'A calm, optional suggestion.',
      options: const ['open', 'no_thanks'],
    );
