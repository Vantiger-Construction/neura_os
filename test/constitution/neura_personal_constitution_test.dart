import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';
import 'package:neuro_companion/intent_compiler/neura_action_graph.dart';

void main() {
  const defaultConstitution = NeuraPersonalConstitution();

  NeuraActionStep action(
    NeuraActionEffect effect, {
    bool sensitive = false,
    bool workRelated = false,
  }) {
    return NeuraActionStep(
      id: 'test',
      title: 'Test',
      description: 'Test action',
      effect: effect,
      requiredApproval: NeuraApprovalTier.none,
      reversible: true,
      estimatedMinutes: 1,
      priority: 1,
      containsSensitiveContent: sensitive,
      isWorkRelated: workRelated,
    );
  }

  test('default constitution blocks purchases, messages, and cloud AI', () {
    final at = DateTime.utc(2026, 8, 22, 15);

    expect(
      defaultConstitution.evaluate(
        action(NeuraActionEffect.purchase),
        at: at,
      ).allowed,
      isFalse,
    );
    expect(
      defaultConstitution.evaluate(
        action(NeuraActionEffect.externalMessage),
        at: at,
      ).allowed,
      isFalse,
    );
    expect(
      defaultConstitution.evaluate(
        action(NeuraActionEffect.cloudRequest),
        at: at,
      ).allowed,
      isFalse,
    );
  });

  test('allowed external message still requires elevated preview approval', () {
    final constitution = defaultConstitution.copyWith(
      allowExternalMessages: true,
    );

    final decision = constitution.evaluate(
      action(NeuraActionEffect.externalMessage),
      at: DateTime.utc(2026, 8, 22, 15),
    );

    expect(decision.allowed, isTrue);
    expect(decision.requiredApproval, NeuraApprovalTier.elevated);
  });

  test('sensitive content cannot cross the cloud-locality boundary', () {
    final constitution = defaultConstitution.copyWith(allowCloudAi: true);

    final decision = constitution.evaluate(
      action(NeuraActionEffect.cloudRequest, sensitive: true),
      at: DateTime.utc(2026, 8, 22, 15),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('Sensitive content'));
  });

  test('Safe Mode blocks an otherwise allowed calendar effect', () {
    final decision = defaultConstitution.evaluate(
      action(NeuraActionEffect.calendar),
      at: DateTime.utc(2026, 8, 22, 15),
      safeMode: true,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('Safe Mode'));
  });
}
