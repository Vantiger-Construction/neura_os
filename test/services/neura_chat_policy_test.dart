import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_chat_policy.dart';

void main() {
  group('NeuraChatPolicy', () {
    test('private reflection room is working-memory only', () {
      final policy = NeuraChatPolicy.forRoom('reflection_bay');
      expect(policy.persistMemory, isFalse);
      expect(policy.allowsTool(NeuraChatPolicy.getMoodHistory), isTrue);
      expect(policy.allowsTool(NeuraChatPolicy.dispatchIntent), isFalse);
    });

    test('legacy vault remains persistent', () {
      final policy = NeuraChatPolicy.forRoom('legacy_vault');
      expect(policy.persistMemory, isTrue);
      expect(policy.allowsTool(NeuraChatPolicy.dispatchIntent), isTrue);
    });

    test('advertised tools exactly match allow list', () {
      final policy = NeuraChatPolicy.forRoom('mood_den');
      final names = NeuraChatPolicy.advertisedTools(policy)
          .map((tool) => tool['name'])
          .toSet();
      expect(names, policy.allowedTools);
    });

    test('unknown rooms fall back to penthouse policy', () {
      final policy = NeuraChatPolicy.forRoom('does_not_exist');
      expect(policy.roomId, 'penthouse');
      expect(policy.persistMemory, isTrue);
    });
  });
}
