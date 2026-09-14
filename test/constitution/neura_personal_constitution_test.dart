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

  test('default constitution blocks purchases and external messages', () {
    final at = DateTime.utc(2026, 8, 22, 15);

    expect(
      defaultConstitution
          .evaluate(action(NeuraActionEffect.purchase), at: at)
          .allowed,
      isFalse,
    );
    expect(
      defaultConstitution
          .evaluate(action(NeuraActionEffect.externalMessage), at: at)
          .allowed,
      isFalse,
    );
  });

  test(
      'default constitution allows cloud AI -- chat is the core feature and '
      'most users never open this settings screen', () {
    final decision = defaultConstitution.evaluate(
      action(NeuraActionEffect.cloudRequest),
      at: DateTime.utc(2026, 8, 22, 15),
    );

    expect(decision.allowed, isTrue);
    expect(decision.requiredApproval, NeuraApprovalTier.elevated);
  });

  test('an explicitly locked-down constitution can still disable cloud AI', () {
    final locked = defaultConstitution.copyWith(allowCloudAi: false);

    expect(
      locked
          .evaluate(
            action(NeuraActionEffect.cloudRequest),
            at: DateTime.utc(2026, 8, 22, 15),
          )
          .allowed,
      isFalse,
    );
  });

  group('evaluateEffect', () {
    test('matches evaluate for the same effect and flags', () {
      final at = DateTime.utc(2026, 8, 22, 15);
      final viaAction = defaultConstitution.evaluate(
        action(NeuraActionEffect.externalMessage, sensitive: true),
        at: at,
      );
      final viaEffect = defaultConstitution.evaluateEffect(
        effect: NeuraActionEffect.externalMessage,
        at: at,
        containsSensitiveContent: true,
      );

      expect(viaEffect.allowed, viaAction.allowed);
      expect(viaEffect.reason, viaAction.reason);
      expect(viaEffect.requiredApproval, viaAction.requiredApproval);
    });

    test('can be called without a NeuraActionStep at all', () {
      final decision = defaultConstitution.evaluateEffect(
        effect: NeuraActionEffect.localRead,
        at: DateTime.utc(2026, 8, 22, 15),
      );

      expect(decision.allowed, isTrue);
      expect(decision.requiredApproval, NeuraApprovalTier.none);
    });
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
